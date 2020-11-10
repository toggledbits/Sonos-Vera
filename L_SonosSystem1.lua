--[[
	Sonos Plugin for Vera and openLuup
	Current maintainer: rigpapa https://community.getvera.com/u/rigpapa/summary
	Github repository: https://github.com/toggledbits/Sonos-Vera
	For license information, please see the above repository.
--]]

module( "L_SonosSystem1", package.seeall )

PLUGIN_NAME = "Sonos"
PLUGIN_VERSION = "2.0-hotfix20314.1625"
PLUGIN_ID = 4226
PLUGIN_URL = "https://github.com/toggledbits/Sonos-Vera"

local _CONFIGVERSION = 20136
local _UIVERSION = 20103

local DEBUG_MODE = false	-- Don't hardcode true--use state variable config

local DEVELOPMENT = false	-- ??? Dev: false for production

local MIN_UPNP_VERSION = 20103	-- Minimum version of L_SonosUPnP that works
local MIN_TTS_VERSION = 20286	-- Minimum version of L_SonosTTS that works

local MSG_CLASS = "Sonos"
local isOpenLuup = false
local isALTUI = false
local pluginDevice
local logFile = false
local unsafeLua = true

local taskHandle = -1 -- luup.task use
local TASK_ERROR = 2
local TASK_ERROR_PERM = -2
local TASK_SUCCESS = 4
-- local TASK_BUSY = 1

local VERA_LOCAL_IP
local VERA_IP
local VERA_WEB_PORT = 80

local UPNP_AVTRANSPORT_SERVICE = 'urn:schemas-upnp-org:service:AVTransport:1'
local UPNP_RENDERING_CONTROL_SERVICE = 'urn:schemas-upnp-org:service:RenderingControl:1'
local UPNP_GROUP_RENDERING_CONTROL_SERVICE = 'urn:schemas-upnp-org:service:GroupRenderingControl:1'
local UPNP_DEVICE_PROPERTIES_SERVICE = 'urn:schemas-upnp-org:service:DeviceProperties:1'
-- local UPNP_CONNECTION_MANAGER_SERVICE = 'urn:schemas-upnp-org:service:ConnectionManager:1'
local UPNP_ZONEGROUPTOPOLOGY_SERVICE = 'urn:schemas-upnp-org:service:ZoneGroupTopology:1'
local UPNP_MUSICSERVICES_SERVICE = 'urn:schemas-upnp-org:service:MusicServices:1'
local UPNP_MR_CONTENT_DIRECTORY_SERVICE = 'urn:schemas-upnp-org:service:ContentDirectory:1'

local UPNP_AVTRANSPORT_SID = 'urn:upnp-org:serviceId:AVTransport'
local UPNP_RENDERING_CONTROL_SID = 'urn:upnp-org:serviceId:RenderingControl'
-- local UPNP_GROUP_RENDERING_CONTROL_SID = 'urn:upnp-org:serviceId:GroupRenderingControl'
local UPNP_DEVICE_PROPERTIES_SID = 'urn:upnp-org:serviceId:DeviceProperties'
-- local UPNP_CONNECTION_MANAGER_SID = 'urn:upnp-org:serviceId:ConnectionManager'
local UPNP_ZONEGROUPTOPOLOGY_SID = 'urn:upnp-org:serviceId:ZoneGroupTopology'
-- local UPNP_MUSICSERVICES_SID = 'urn:upnp-org:serviceId:MusicServices'
local UPNP_MR_CONTENT_DIRECTORY_SID = 'urn:upnp-org:serviceId:ContentDirectory'

if (package.path:find("/etc/cmh-ludl/?.lua;/etc/cmh-lu/?.lua", 1, true) == nil) then
	package.path = package.path..";/etc/cmh-ludl/?.lua;/etc/cmh-lu/?.lua"
end
package.loaded.L_SonosUPnP = nil
package.loaded.L_SonosTTS = nil
local _,upnp = pcall( require, "L_SonosUPnP" )
if type( upnp ) ~= "table" then error "Sonos: invalid installation; the L_SonosUPnP module could not be loaded." end
local _,tts = pcall( require, "L_SonosTTS" )
if type( tts ) ~= "table" then tts = nil end

local _,url = pcall( require, "socket.url" )
local _,lom = pcall( require,  "lxp.lom" )
local _,json = pcall( require, "dkjson" )
local _,lfs = pcall( require, "lfs" )

-- Table of Sonos IP addresses indexed by Vera devices
local port = 1400
local descriptionURL = "http://%s:%s/xml/device_description.xml"
local iconURL = "../../../icons/Sonos.png"

local HADEVICE_SID = "urn:micasaverde-com:serviceId:HaDevice1"
local SONOS_ZONE_SID = "urn:micasaverde-com:serviceId:Sonos1"
local SONOS_ZONE_DEVICE_TYPE = "urn:schemas-micasaverde-com:device:Sonos:1"
local SONOS_SYS_SID = "urn:toggledbits-com:serviceId:SonosSystem1"
local SONOS_SYS_DEVICE_TYPE = "urn:schemas-toggledbits-com:device:SonosSystem:1"

local ZoneSubscriptionsTemplate = {
	{
		service=UPNP_AVTRANSPORT_SERVICE,
		eventVariable="LastChange",
		actionName="NotifyAVTransportChange"
	},
	{
		service=UPNP_RENDERING_CONTROL_SERVICE,
		eventVariable="LastChange",
		actionName="NotifyRenderingChange"
	}
}

local MasterSubscriptionsTemplate = {
	{
		service=UPNP_ZONEGROUPTOPOLOGY_SERVICE,
		eventVariable="ZoneGroupState",
		actionName="NotifyZoneGroupTopologyChange"
	},
	{
		service=UPNP_MR_CONTENT_DIRECTORY_SERVICE,
		eventVariable="ContainerUpdateIDs",
		actionName="NotifyContentDirectoryChange"
	}
}

local EventSubscriptions = {} -- per UUID

local PLUGIN_ICON = "Sonos.png"

local QUEUE_URI = "x-rincon-queue:%s#0"

local playbackCxt = {}
local sayPlayback = {}

-- Zone group topology (set by updateZoneInfo())
local systemReady = false
local zoneInfo = false
local masterZones = {}

local metaDataKeys = {}
local dataTable = {}

local sonosServices = false

local variableSidTable = {
	TransportState = UPNP_AVTRANSPORT_SID,
	TransportStatus = UPNP_AVTRANSPORT_SID,
	TransportPlaySpeed = UPNP_AVTRANSPORT_SID,
	CurrentPlayMode = UPNP_AVTRANSPORT_SID,
	CurrentCrossfadeMode = UPNP_AVTRANSPORT_SID,
	CurrentTransportActions = UPNP_AVTRANSPORT_SID,
	NumberOfTracks = UPNP_AVTRANSPORT_SID,
	CurrentMediaDuration = UPNP_AVTRANSPORT_SID,
	AVTransportURI = UPNP_AVTRANSPORT_SID,
	AVTransportURIMetaData = UPNP_AVTRANSPORT_SID,
	CurrentRadio = UPNP_AVTRANSPORT_SID,
	CurrentService = SONOS_ZONE_SID,
	CurrentTrack = UPNP_AVTRANSPORT_SID,
	CurrentTrackDuration = UPNP_AVTRANSPORT_SID,
	CurrentTrackURI = UPNP_AVTRANSPORT_SID,
	CurrentTrackMetaData = UPNP_AVTRANSPORT_SID,
	CurrentStatus = UPNP_AVTRANSPORT_SID,
	CurrentTitle = UPNP_AVTRANSPORT_SID,
	CurrentArtist = UPNP_AVTRANSPORT_SID,
	CurrentAlbum = UPNP_AVTRANSPORT_SID,
	CurrentDetails = UPNP_AVTRANSPORT_SID,
	CurrentAlbumArt = UPNP_AVTRANSPORT_SID,
	RelativeTimePosition = UPNP_AVTRANSPORT_SID,

	Volume = UPNP_RENDERING_CONTROL_SID,
	Mute = UPNP_RENDERING_CONTROL_SID,
	Bass = UPNP_RENDERING_CONTROL_SID,
	Treble = UPNP_RENDERING_CONTROL_SID,
	Loudness = UPNP_RENDERING_CONTROL_SID,
	OutputFixed = UPNP_RENDERING_CONTROL_SID,

	Queue = UPNP_MR_CONTENT_DIRECTORY_SID,

	GroupCoordinator = SONOS_ZONE_SID,
	ZonePlayerUUIDsInGroup = UPNP_ZONEGROUPTOPOLOGY_SID,

	SonosOnline = SONOS_ZONE_SID,
	ZoneName = UPNP_DEVICE_PROPERTIES_SID,
	SonosID = UPNP_DEVICE_PROPERTIES_SID,
	SonosModelName = SONOS_ZONE_SID,
	SonosModel = SONOS_ZONE_SID,
	SonosModelNumber = SONOS_ZONE_SID
}

local BROWSE_TIMEOUT = 5
local fetchQueue = true

local idConfRefresh = 0

-- TTS queue and support
local sayQueue = {}
local cacheTTS = true
local TTSBasePath
local TTSBaseURL
local TTSConfig
local TTS_METADATA = [[<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
	<item id="VERA_TTS" parentID="-1" restricted="1">
		<dc:title>%s</dc:title>
		<res protocolInfo="%s">%s</res>
		<upnp:class>object.item.audioItem.musicTrack</upnp:class>
	</item>
</DIDL-Lite>]]
local TTSChime

local scheduler

local function Q(...) return "'" .. string.gsub(table.concat( arg, "" ), "(')", "\\%1") .. "'" end -- luacheck: ignore 212

local function dump(t, seen)
	if t == nil then return "nil" end
	seen = seen or {}
	local sep = ""
	local str = "{ "
	for k,v in pairs(t) do
		local val
		if type(v) == "table" then
			if seen[v] then val = "(recursion)"
			else
				seen[v] = true
				val = dump(v, seen)
			end
		elseif type(v) == "string" then
			val = string.format("%q", v)
		elseif type(v) == "number" and (math.abs(v-os.time()) <= 86400) then
			val = tostring(v) .. "(" .. os.date("%x.%X", v) .. ")"
		else
			val = tostring(v)
		end
		str = str .. sep .. k .. "=" .. val
		sep = ", "
	end
	str = str .. " }"
	return str
end

local logToFile
local function L(msg, ...) -- luacheck: ignore 212
	local str
	local level = 50
	if type(msg) == "table" then
		str = tostring(msg.prefix or MSG_CLASS) .. ": " .. tostring(msg.msg or msg[1])
		level = msg.level or level
	else
		str = MSG_CLASS .. ": " .. tostring(msg)
	end
	str = string.gsub(str, "%%(%d+)", function( n )
			n = tonumber(n, 10)
			if n < 1 or n > #arg then return "nil" end
			local val = arg[n]
			if type(val) == "table" then
				return dump(val)
			elseif type(val) == "string" then
				return string.format("%q", val)
			elseif type(val) == "number" and math.abs(val-os.time()) <= 86400 then
				return tostring(val) .. "(" .. os.date("%x.%X", val) .. ")"
			end
			return tostring(val)
		end
	)
	luup.log(str, math.max(1, level))
	if logFile then
		pcall( logToFile, str, level )
	end
	if level == 0 and debug and debug.traceback then luup.log( debug.traceback(), 1 ) error(str) end
end

local function W(msg, ...)
	L({msg=msg,level=2}, ...)
	-- if debug and debug.traceback then luup.log( debug.traceback(), 2 ) end
end

local function E(msg, ...)
	L({msg=msg,level=1}, ...)
	if debug and debug.traceback then luup.log( debug.traceback(), 2 ) end
end

local function D(msg, ...)
	if DEBUG_MODE then L({msg="[debug] "..msg, level=50}, ...) end
end

local function split( str, sep )
	sep = sep or ","
	local arr = {}
	if str == nil or #str == 0 then return arr, 0 end
	local rest = string.gsub( str or "", "([^" .. sep .. "]*)" .. sep, function( m ) table.insert( arr, m ) return "" end )
	table.insert( arr, rest )
	return arr
end

-- Clone table (shallow copy)
local function clone( sourceArray )
	local newArray = {}
	for ix,element in pairs( sourceArray or {} ) do
		newArray[ix] = element
	end
	return newArray
end

local function deepCopy( sourceArray, dest )
	dest = dest or {}
	for key,val in pairs( sourceArray or {} ) do
		if type(val) == "table" then
			dest[key] = deepCopy( val )
		else
			dest[key] = val
		end
	end
	return dest
end

local function keys( sourceTable )
	local newArray = {}
	for k in pairs( sourceTable ) do table.insert( newArray, k ) end
	return newArray
end

local function map( sourceTable, func, destMap )
	destMap = destMap or {}
	for k,v in pairs( sourceTable ) do
		if func then
			v,k = func(k, v)
		end
		destMap[v] = k
	end
	return destMap
end

local function xmlescape( t ) return ( t:gsub( '"', "&quot;" ):gsub( "'", "&apos;" ):gsub( "%&", "&amp;" ):gsub( "%<", "&lt;" ):gsub( "%>", "&gt;" ) ) end

local Zones = {}
local function findDeviceByUUID( zoneUUID )
	if not Zones[zoneUUID] then
		for k,v in pairs( luup.devices ) do
			if v.device_type == SONOS_ZONE_DEVICE_TYPE and v.id == zoneUUID then
				Zones[zoneUUID] = k
				break
			end
		end
	end
	if not Zones[zoneUUID] then W("findDeviceByUUID() no device for %1", zoneUUID) end
	return Zones[zoneUUID]
end

local function findZoneByDevice( device )
	local uuid = (luup.devices[tonumber(device) or -1] or {}).id
	if not uuid then W("findZoneByDevice() no zone for %1", device) end
	return uuid
end

-- Initialize a variable if it does not already exist.
local function initVar( name, dflt, dev, sid )
	assert( dev ~= nil )
	assert( sid ~= nil, "SID required for "..tostring(name) )
	local currVal = luup.variable_get( sid, name, dev )
	if currVal == nil then
		luup.variable_set( sid, name, tostring(dflt), dev )
		return dflt
	end
	return currVal
end

-- Set variable, only if value has changed.
local function setVar( sid, name, val, dev )
	if dev <= 1 then E("Invalid device number %1", dev) end
	assert( dev ~= nil and type(dev) == "number", "Invalid set device for "..dump({sid=sid,name=name,val=val,dev=dev}) )
	assert( dev > 0, "Invalid device number "..tostring(dev) )
	assert( sid ~= nil, "SID required for "..tostring(name) )
	val = (val == nil) and "" or tostring(val)
	local s = luup.variable_get( sid, name, dev )
	-- D("setVar(%1,%2,%3,%4) old value %5", sid, name, val, dev, s )
	if s ~= val then
		luup.variable_set( sid, name, val, dev )
	end
	return s
end

-- Get variable or default
local function getVar( name, dflt, dev, sid, doinit )
	assert( name ~= nil )
	assert( dev ~= nil )
	assert( sid ~= nil, "SID required for "..tostring(name) )
	local s = luup.variable_get( sid, name, dev )
	if s == nil and doinit then
		luup.variable_set( sid, name, tostring(dflt), dev )
		return dflt
	end
	return (s or "") == "" and dflt or s
end

-- Get numeric variable, or return default value if not set or blank
local function getVarNumeric( name, dflt, dev, sid, doinit )
	local s = getVar( name, dflt, dev, sid, doinit )
	if s == "" then return dflt end
	return tonumber(s) or dflt
end

-- Delete var. Works only on newer firmware; var goes blank on older, which is acceptable.
local function deleteVar( sid, name, dev )
	if luup.variable_get( sid, name, dev ) ~= nil then
		luup.variable_set( sid, name, nil, dev )
	end
end

-- Return true if file exists; optionally returns handle to open file if exists.
local function file_exists( fpath, leaveOpen )
	if lfs and not leaveOpen then
		return lfs.attributes( fpath, "size" ) and true or false
	end
	local f = io.open( fpath, "r" )
	if not f then return false end
	if not leaveOpen then f:close() f=nil end
	return true, f
end

-- Return true if plain file or file with lzo suffix exists.
local function file_exists_LZO( fpath )
	if file_exists( fpath ) then return true end
	return file_exists( fpath .. ".lzo" )
end

local function file_symlink( old, new )
	if lfs and lfs.link then
		lfs.link( old, new, true )
	else
		os.execute( "ln -sf '" .. old .. "' '" .. new .. "'" )
	end
end

local function getInstallPath()
	if isOpenLuup then
		local loader = require "openLuup.loader"
		if loader.find_file == nil then
			W("This version of the Sonos plugin requires openLuup 2018.11.21 or higher")
			return "./" -- punt
		end
		return loader.find_file( "L_SonosSystem1.lua" ):gsub( "L_SonosSystem1.lua$", "" )
	end
	return "/etc/cmh-ludl/"
end

-- Log message to log file.
logToFile = function(str, level)
	local lfn = getInstallPath() .. "Sonos.log"
	if logFile == false then
		logFile = io.open(lfn, "a")
		-- Yes, we leave nil if it can't be opened, and therefore don't
		-- keep trying to open as a result. By design.
		if not isOpenLuup then
			os.execute( "ln -sf '" .. lfn .. "' /www/sonos/" )
		end
	end
	if logFile then
		local maxsizek = getVarNumeric("MaxLogSize", DEVELOPMENT and 512 or 0, pluginDevice, SONOS_SYS_SID)
		if maxsizek <= 0 then
			-- We should not be open now (runtime change, no reload needed)
			logFile:close()
			logFile = false
			return
		end
		if logFile:seek("end") >= (1024*maxsizek) then
			logFile:close()
			os.execute("pluto-lzo c '" .. lfn .. "' '" .. lfn .. "-prev.lzo'")
			logFile = io.open(lfn, "w")
			if not logFile then return end
			logFile:write(string.format("Log rotated; plugin %s; luup %2\n", PLUGIN_VERSION, luup.version))
		end
		level = level or 50
		logFile:write(string.format("%02d %s %s\n", level, os.date("%x.%X"), str))
		logFile:flush()
	end
end

TaskManager = function( luupCallbackName )
	local callback = luupCallbackName
	local runStamp = 1
	local tickTasks = { __sched={ id="__sched" } }
	local Task = { id=false, when=0 }
	local nextident = 0

	-- Schedule a timer tick for a future (absolute) time. If the time is sooner than
	-- any currently scheduled time, the task tick is advanced; otherwise, it is
	-- ignored (as the existing task will come sooner), unless repl=true, in which
	-- case the existing task will be deferred until the provided time.
	local function scheduleTick( tkey, timeTick, flags )
		local tinfo = tickTasks[tkey]
		assert( tinfo, "Task not found" )
		assert( type(timeTick) == "number" and timeTick > 0, "Invalid schedule time" )
		flags = flags or {}
		if ( tinfo.when or 0 ) == 0 or timeTick < tinfo.when or flags.replace then
			-- Not scheduled, requested sooner than currently scheduled, or forced replacement
			tinfo.when = timeTick
		end
		-- If new tick is earlier than next plugin tick, reschedule Luup timer
		if tickTasks.__sched.when == 0 then return end -- in queue processing
		if tickTasks.__sched.when == nil or timeTick < tickTasks.__sched.when then
			tickTasks.__sched.when = timeTick
			local delay = timeTick - os.time()
			if delay < 0 then delay = 0 end
			runStamp = runStamp + 1
			luup.call_delay( callback, delay, runStamp )
		end
	end

	-- Remove tasks from queue. Should only be called from Task::close()
	local function removeTask( tkey )
		tickTasks[ tkey ] = nil
	end

	-- Plugin timer tick. Using the tickTasks table, we keep track of
	-- tasks that need to be run and when, and try to stay on schedule. This
	-- keeps us light on resources: typically one system timer only for any
	-- number of devices.
	local function runReadyTasks( luupCallbackArg )
		local stamp = tonumber(luupCallbackArg)
		if stamp ~= runStamp then
			-- runStamp changed, different from stamp on this call, just exit.
			return
		end

		local now = os.time()
		local nextTick = nil
		tickTasks.__sched.when = 0 -- marker (run in progress)

		-- Since the tasks can manipulate the tickTasks table (via calls to
		-- scheduleTick()), the iterator is likely to be disrupted, so make a
		-- separate list of tasks that need service (to-do list).
		local todo = {}
		for t,v in pairs(tickTasks) do
			if t ~= "__sched" and ( v.when or 0 ) ~= 0 and v.when <= now then
				D("Task:runReadyTasks() ready %1 %2", v.id, v.when)
				table.insert( todo, v )
			end
		end

		-- Run the to-do list tasks.
		table.sort( todo, function( a, b ) return a.when < b.when end )
		for _,v in ipairs(todo) do
			D("Task:runReadyTasks() running %1", v.id)
			v:run()
		end

		-- Things change while we work. Take another pass to find next task.
		for t,v in pairs(tickTasks) do
			D("Task:runReadyTasks() waiting %1 %2", v.id, v.when)
			if t ~= "__sched" and ( v.when or 0 ) ~= 0 then
				if nextTick == nil or v.when < nextTick then
					nextTick = v.when
				end
			end
		end

		-- Reschedule scheduler if scheduled tasks pending
		if nextTick ~= nil then
			now = os.time() -- Get the actual time now; above tasks can take a while.
			local delay = nextTick - now
			if delay < 0 then delay = 0 end
			tickTasks.__sched.when = now + delay -- that may not be nextTick
			D("Task:runReadyTasks() next in %1", delay)
			luup.call_delay( callback, delay, luupCallbackArg )
		else
			tickTasks.__sched.when = nil -- remove when to signal no timer running
		end
	end

	function Task:schedule( when, flags, args )
		assert(self.id, "Can't reschedule() a closed task")
		if args then self.args = args end
		scheduleTick( self.id, when, flags )
		return self
	end

	function Task:delay( delay, flags, args )
		assert(self.id, "Can't delay() a closed task")
		if args then self.args = args end
		scheduleTick( self.id, os.time()+delay, flags )
		return self
	end

	function Task:suspend()
		self.when = 0
		return self
	end

	function Task:suspended() return self.when == 0 end

	function Task:run()
		assert(self.id, "Can't run() a closed task")
		self.when = 0
		local success, err = pcall( self.func, self, unpack( self.args or {} ) )
		if not success then L({level=1, msg="Task:run() task %1 failed: %2"}, self, err) end
		return self
	end

	function Task:close()
		removeTask( self.id )
		self.id = nil
		self.when = nil
		self.args = nil
		self.func = nil
		setmetatable(self,nil)
		return self
	end

	function Task:new( id, owner, tickFunction, args, desc )
		assert( id == nil or tickTasks[tostring(id)] == nil,
			"Task already exists with id "..tostring(id)..": "..tostring(tickTasks[tostring(id)]) )
		assert( type(owner) == "number" )
		assert( type(tickFunction) == "function" )

		local obj = { when=0, owner=owner, func=tickFunction, name=desc or tostring(owner), args=args }
		obj.id = tostring( id or obj )
		setmetatable(obj, self)
		self.__index = self
		self.__tostring = function(e) return string.format("Task(%s)", e.id) end

		tickTasks[ obj.id ] = obj
		return obj
	end

	local function getOwnerTasks( owner )
		local res = {}
		for k,v in pairs( tickTasks ) do
			if owner == nil or v.owner == owner then
				table.insert( res, k )
			end
		end
		return res
	end

	local function getTask( id )
		return tickTasks[tostring(id)]
	end

	-- Convenience function to create a delayed call to the given func in its own task
	local function delay( func, delaySecs, args )
		nextident = nextident + 1
		local t = Task:new( "_delay"..nextident, pluginDevice, func, args )
		t:delay( math.max(0, delaySecs) )
		return t
	end

	return {
		runReadyTasks = runReadyTasks,
		getOwnerTasks = getOwnerTasks,
		getTask = getTask,
		delay = delay,
		Task = Task,
		_tt = tickTasks
	}
end

-- Tick handler for scheduler (TaskManager)
-- @export
function sonosTick( stamp )
	D("sonosTick(%1)", stamp)
	scheduler.runReadyTasks( stamp )
end

local function SonosReload()
	W( 'Requesting luup reload...' )
	luup.reload()
end

local luupTask
local function clearLuupTask( stask )
	luupTask("Clearing...", TASK_SUCCESS)
	stask:close()
end

luupTask = function(text, mode)
	D("luupTask(%1,%2)", text, mode)
	if (mode == TASK_ERROR_PERM) then
		taskHandle = luup.task(text, TASK_ERROR, MSG_CLASS, taskHandle)
	else
		taskHandle = luup.task(text, mode, MSG_CLASS, taskHandle)

		-- Clear the previous error, since they're all transient
		if (mode ~= TASK_SUCCESS) then
			local t = scheduler.getTask("clearLuupTask")
			if not t then
				t = scheduler.Task:new( "clearLuupTask", pluginDevice, clearLuupTask)
			end
			t:delay(30, { replace=true })
		end
	end
end

local function defaultValue(arr, val, default)
	local ret = (arr or {})[val] or ""
	if "" == ret then return default end
	return ret
end

local function useProxy()
	return getVarNumeric( "UseProxy", isOpenLuup and 0 or 1, pluginDevice, SONOS_SYS_SID ) ~= 0 and
		upnp.proxyVersionAtLeast(1)
end

-- Set local and state variable data for zone. `zoneident` can be device number or zone UUID.
-- Every caller should use ident; the use of device number is deprecated.
local function setData(name, value, uuid, default)
	if not string.match(tostring(uuid), "^RINCON_") then
		W("setData(%1,%2) reference object invalid UUID %3", name, value, uuid)
	elseif uuid then
		-- The shadow table stores the value whether there's a device for the zone or not
		dataTable[uuid] = dataTable[uuid] or {}
		local curValue = dataTable[uuid][name]
		if value == nil or value ~= curValue then
			-- Use state variables as well for known devices
			dataTable[uuid][name] = value
			local device = findDeviceByUUID( uuid )
			if not device then
				W("No device for zone %1; reload luup to inventory/discover.", uuid)
			elseif variableSidTable[name] then
				setVar( variableSidTable[name], name, value == nil and "" or tostring(value), device )
--[[
			else
				D("No serviceId defined for %1; state variable value not saved", name)
--]]
			end
			return true -- flag something changed
		end
	end
	return default or false -- flag nothing changed
end

local setVariableValue = setVar -- alias to old

--
-- Put together a rudimentary status string for the Dashboard
--
local function getSimpleDIDLStatus(meta)
	local title = ""
	local artist = ""
	local album = ""
	local details = ""
	local albumArt = ""
	local desc = ""
	local didl = nil
	local didlTable = nil
	local complement = ""
	if (meta ~= nil and meta ~= "") then
		didl, didlTable = upnp.parseDIDLItem(meta)

		desc = didlTable["desc"] or desc
		if (didlTable["upnp:class"] == "object.item") then
			title = upnp.decode(didlTable["dc:title"] or title)
			details = upnp.decode(didlTable["r:streamContent"] or details)
			if (details ~= "") then
				if (string.sub(title, 1, 10) ~= "x-sonosapi") then
					complement = ": "
				end
				complement = complement .. details
			end
			if (didlTable["upnp:albumArtURI"] ~= nil) then
				albumArt = upnp.decode(didlTable["upnp:albumArtURI"])
			end
		elseif ((didlTable["upnp:class"] == "object.item.audioItem.musicTrack")
				or (didlTable["upnp:class"] == "object.item.audioItem")) then
			title = upnp.decode(didlTable["dc:title"] or title)
			artist = upnp.decode(didlTable["r:albumArtist"] or didlTable["dc:creator"] or artist)
			album = upnp.decode(didlTable["upnp:album"] or album)
			details = upnp.decode(didlTable["r:streamContent"] or details)
			local title2, artist2 = details:match(".*|TITLE ([^|]*)|ARTIST ([^|]*)")
			if (title2 ~= nil) then
				title = title2
			end
			if (artist2 ~= nil) then
				artist = artist2
			end
			if (didlTable["upnp:albumArtURI"] ~= nil) then
				albumArt = upnp.decode(didlTable["upnp:albumArtURI"])
			end
			if (artist ~= "" and album ~= "") then
				complement = string.format(" (%s, %s)", artist, album)
			elseif (artist ~= "") then
				complement = string.format(" (%s)", artist)
			elseif (album ~= "") then
				complement = string.format(" (%s)", album)
			end
		elseif (didlTable["upnp:class"] == "object.item.audioItem.audioBroadcast") then
			title = upnp.decode(didlTable["dc:title"] or title)
		end
	end
	return complement, title, artist, album, details, albumArt, desc, didl, didlTable
end

function xmlNodesForTag( node, tag )
	local n = 0
	return function()
		while n < #node do
			n = n + 1
			if type( node[n] ) == "table" and node[n].tag == tag then return node[n] end
		end
		return nil
	end
end

-- Parse the ZoneGroupState response and create the zoneInfo table. The `zones` subtable
-- contains the info for each zone. The `groups` subtable contains an entry for each group
-- with UUID (group ID) and Coordinator (UUID of zone that is group coordinator), and a `members`
-- array of zone UUIDs. The zoneInfo table is meant to provide fast, consistent indexing and
-- data access for all zones and groups.
local zoneInfoMemberAttributes = { "UUID", "Location", "ZoneName", "HTSatChanMapSet", "IsZoneBridge", "Invisible" }
function updateZoneInfo( zs )
	-- D("updateZoneInfo(%1)", zs)
	D("updateZoneInfo(<xml>)")
	-- D("updateZoneInfo() zone info is \r\n%1", zs)
	local root = lom.parse( zs )
	assert( root and root.tag, "Invalid zone topology data:\n"..zs )
	-- PHR??? This is odd. Response for at least one users' configuration does not include <ZoneGroupState> enclosing tag.
	D("updateZoneInfo() zone topology data root tag is %1", root.tag)
	local groups
	if root.tag == "ZoneGroupState" then
		groups = xmlNodesForTag( root, "ZoneGroups" )()
	elseif root.tag == "ZoneGroups" then
		groups = root
	end
	zoneInfo = { zones={}, groups={} }
	if not groups then return end -- probably no data yet
	for v in xmlNodesForTag( groups, "ZoneGroup" ) do
		local gr = { UUID=v.attr.ID, Coordinator=v.attr.Coordinator, members={} }
		zoneInfo.groups[v.attr.ID] = gr
		for v2 in xmlNodesForTag( v, "ZoneGroupMember" ) do
			local zi = {}
			for _,v3 in ipairs( zoneInfoMemberAttributes ) do
				zi[v3] = tonumber( v2.attr[v3] ) or v2.attr[v3]
			end
			zi.Group = gr.UUID
			zoneInfo.zones[v2.attr.UUID] = zi
			table.insert( gr.members, v2.attr.UUID )

			for sat in xmlNodesForTag( v2, "Satellite" ) do
				D("updateZoneInfo() zone %1 has satellite %2", v2.attr.UUID, sat.attr.UUID)
				zi = {}
				for _,v3 in ipairs( zoneInfoMemberAttributes ) do
					zi[v3] = tonumber( sat.attr[v3] ) or sat.attr[v3]
				end
				zi.Group = false
				zi.isSatellite = true
				zi.Base = v2.attr.UUID
				zoneInfo.zones[sat.attr.UUID] = zi
				zoneInfo.zones[zi.Base].Satellites = zoneInfo.zones[zi.Base].Satellites or {}
				table.insert( zoneInfo.zones[zi.Base].Satellites, sat.attr.UUID )
			end
		end
		table.sort( gr.members ) -- sort for deterministic variable handling
	end
	D("updateZoneInfo() updated zoneInfo: %1", zoneInfo)
	setVar( SONOS_SYS_SID, "zoneInfo", json.encode( zoneInfo ), pluginDevice )

	-- Update data fields
	for uuid,zd in pairs( zoneInfo.zones ) do
		local changed = false
		if zd.Group then
			local gr = zoneInfo.groups[ zd.Group ] or {}
			changed = setData("ZonePlayerUUIDsInGroup", table.concat( gr.members or {}, "," ), uuid, changed)
			changed = setData("GroupCoordinator", gr.Coordinator or "", uuid, changed)
		end
		if changed and ( Zones[uuid] or -1 ) > 0 then
			D("updateZoneInfo() modified zone group for %1 #%2", uuid, Zones[uuid])
			setVar(HADEVICE_SID, "LastUpdate", os.time(), Zones[uuid])
		end
	end
end

local function getZoneNameFromUUID(uuid)
	return (zoneInfo.zones[uuid] or {}).ZoneName
end

local function getUUIDFromZoneName(name)
	for _,item in pairs( zoneInfo.zones ) do
		if item.ZoneName == name and not item.isSatellite then return item.UUID end
	end
	return nil
end

-- Get IP for zone from zoneInfo (specifically)
local function getIPFromUUID(uuid)
	if zoneInfo then
		local location = (zoneInfo.zones[uuid] or {}).Location
		if location then
			return location:match( "^https?://([^:/]+)")
		end
	end
	return nil
end

-- Return zoneInfo group data for group of which zoneUUID is a member
local function getZoneGroup( zoneUUID )
	local zi = zoneInfo.zones[zoneUUID]
	if not zi then
		W("No zoneInfo for zone %1", zoneUUID)
		return nil
	elseif zi.isSatellite then
		D("getZoneGroup() zone %1 is satellite", zoneUUID)
		return false
	end
	D("getZoneGroup() group info for %1 is %2", zi.Group, zoneInfo.groups[zi.Group])
	return zoneInfo.groups[zi.Group]
end

-- getZoneCoordinator() removed; handled by controlByCoordinator()

-- Return true if zone is group coordinator
local function isGroupCoordinator( zoneUUID )
	local gr = getZoneGroup( zoneUUID ) or {}
	return zoneUUID == gr.Coordinator
end

-- Return group info for the group of which `uuid` is a member
local function getGroupInfo(uuid)
	local groupInfo = getZoneGroup( uuid ) or {}
	return table.concat( groupInfo.members or {}, "," ), groupInfo.Coordinator or uuid, groupInfo.ID
end

local function updateZoneGroupTopology(uuid)
	D("updateZoneGroupTopology(%1)", uuid)

	-- Update network and group information
	local ZoneGroupTopology = upnp.getService(uuid, UPNP_ZONEGROUPTOPOLOGY_SERVICE)
	if ZoneGroupTopology then
		D("updateZoneGroupTopology() refreshing zone group topology")
		local status, tmp = ZoneGroupTopology.GetZoneGroupState({})
		if status then
			local groupsState = upnp.extractElement("ZoneGroupState", tmp, "")
			updateZoneInfo( groupsState )
			return true
		end
	end
	return false
end

-- Get UUIDs for all controllable devices (excludes bridges and satellites)
local function getAllUUIDs()
	local zones = {}
	for zid,zone in pairs( zoneInfo.zones ) do
		if zone.IsZoneBridge ~= "1" and not zone.isSatellite then
			table.insert( zones, zid )
		end
	end
	return table.concat( zones, "," ), zones
end

-- Return bool if device is online; pass device number or zone uuid
local function isOnline(uuid)
	if uuid and dataTable[uuid] then
		return tostring(dataTable[uuid].SonosOnline or 0) ~= "0"
	end
	return false
end

local function deviceIsOnline(device)
	local changed = setData("SonosOnline", "1", findZoneByDevice(device), false)
	if changed then
		L("Setting device #%1 on line", device)
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), device)
	end
	return changed
end

local function deviceIsOffline(device)
	local uuid = findZoneByDevice(device)
	local changed = setData("SonosOnline", "0", uuid, false)
	if changed and uuid then
		W("Setting device #%1 to off-line state", device)

		changed = setData("TransportState", "STOPPED", uuid, changed)
		changed = setData("TransportStatus", "KO", uuid, changed)
		changed = setData("TransportPlaySpeed", "1", uuid, changed)
		changed = setData("CurrentPlayMode", "NORMAL", uuid, changed)
		changed = setData("CurrentCrossfadeMode", "0", uuid, changed)
		changed = setData("CurrentTransportActions", "", uuid, changed)
		changed = setData("NumberOfTracks", "NOT_IMPLEMENTED", uuid, changed)
		changed = setData("CurrentMediaDuration", "NOT_IMPLEMENTED", uuid, changed)
		changed = setData("AVTransportURI", "", uuid, changed)
		changed = setData("AVTransportURIMetaData", "", uuid, changed)
		changed = setData("CurrentRadio", "", uuid, changed)
		changed = setData("CurrentService", "", uuid, changed)
		changed = setData("CurrentTrack", "NOT_IMPLEMENTED", uuid, changed)
		changed = setData("CurrentTrackDuration", "NOT_IMPLEMENTED", uuid, changed)
		changed = setData("CurrentTrackURI", "", uuid, changed)
		changed = setData("CurrentTrackMetaData", "", uuid, changed)
		changed = setData("CurrentStatus", "Offline", uuid, changed)
		changed = setData("CurrentTitle", "", uuid, changed)
		changed = setData("CurrentArtist", "", uuid, changed)
		changed = setData("CurrentAlbum", "", uuid, changed)
		changed = setData("CurrentDetails", "", uuid, changed)
		changed = setData("CurrentAlbumArt", PLUGIN_ICON, uuid, changed)
		changed = setData("RelativeTimePosition", "NOT_IMPLEMENTED", uuid, changed)
		changed = setData("Volume", "0", uuid, changed)
		changed = setData("Mute", "0", uuid, changed)
		changed = setData("Queue", "", uuid, changed)
		changed = setData("GroupCoordinator", "", uuid, changed)
		changed = setData("ZonePlayerUUIDsInGroup", "", uuid, changed)

		if EventSubscriptions[uuid] then
			upnp.cancelProxySubscriptions(EventSubscriptions[uuid])
			EventSubscriptions[uuid] = nil
		end
	end

	if device > 0 then
		luup.attr_set( 'invisible', 0, device )
		if changed then
			setVar(SONOS_ZONE_SID, "MasterRole", 0, device)
			setVar(HADEVICE_SID, "LastUpdate", os.time(), device)
		end
	end
end

local function commsFailure(device, text)
	W("Sonos %1 device #%2 (%3) at %4 comm failure. "..tostring(text or ""),
		findZoneByDevice(device), device, (luup.devices[device] or {}).description,
		getVar( "SonosIP", "(no IP)", device or -1, SONOS_ZONE_SID ))
	deviceIsOffline(device)
end

local function allOffline( pdev )
	for k,v in pairs( luup.devices ) do
		if v.device_num_parent == pdev then
			deviceIsOffline( k )
			setVar(UPNP_AVTRANSPORT_SID, "CurrentStatus", "Offline", k)
		end
	end
end

local function getSonosServiceId(serviceName)
	for k, v in pairs(sonosServices or {}) do
		if v == serviceName then
			return k
		end
	end
	return nil
end

local function getServiceFromURI(transportUri, trackUri)
	local serviceName = ""
	local serviceId
	local serviceCmd
	if (transportUri == nil) then
		serviceId = "-1"
	elseif (transportUri:find("pndrradio:") == 1) then
		serviceName = "Pandora"
		serviceId = getSonosServiceId(serviceName)
		if (serviceId == nil) then
			serviceId = "-1"
		end
	else
		serviceCmd, serviceId = transportUri:match("x%-sonosapi%-stream:([^%?]+%?sid=(%d+).*)")
		if (serviceCmd == nil) then
			serviceCmd, serviceId = transportUri:match("x%-sonosapi%-radio:([^%?]+%?sid=(%d+).*)")
		end
		if (serviceCmd == nil) then
			serviceCmd, serviceId = transportUri:match("x%-sonosapi%-hls:([^%?]+%?sid=(%d+).*)")
		end
		if (serviceCmd == nil and trackUri ~= nil) then
			serviceCmd, serviceId = trackUri:match("x%-sonosprog%-http:([^%?]+%?sid=(%d+).*)")
		end
		if (serviceCmd == nil and trackUri ~= nil) then
			serviceCmd, serviceId = trackUri:match("x%-sonos%-http:([^%?]+%?sid=(%d+).*)")
		end
		if (serviceCmd ~= nil and serviceId ~= nil) then
			serviceName = (sonosServices or {})[serviceId] or ""
		end
	end
	return serviceName, serviceId
end

local function updateServicesMetaDataKeys(id, key)
	if (id or "" ) ~= "" and ( key or "" ) ~= "" and metaDataKeys[id] ~= key then
		metaDataKeys[tostring(id)] = key
		local data = {}
		for k, v in pairs(metaDataKeys) do
			table.insert( data, string.format('%s=%s', k, v) )
		end
		setVar(SONOS_SYS_SID, "SonosServicesKeys", table.concat( data, "\n" ), pluginDevice)
	end
end

local function loadServicesMetaDataKeys()
	local k = {}
	local elts = getVar("SonosServicesKeys", "", pluginDevice, SONOS_SYS_SID)
	for line in elts:gmatch( "[^\n]+" ) do
		local s,d = line:match("^([^=]+)=(.*)")
		if s and d then k[tostring(s)] = d end
	end
	D("loadServicesMetaDataKeys() result %1", k)
	return k
end

local function extractDataFromMetaData(zoneUUID, currentUri, currentUriMetaData, trackUri, trackUriMetaData)
	local statusString, info, title, title2, artist, album, details, albumArt, desc
	local uuid = zoneUUID
	_, title, _, _, _, _, desc = getSimpleDIDLStatus(currentUriMetaData)
	info, title2, artist, album, details, albumArt, _ = getSimpleDIDLStatus(trackUriMetaData)
	local service, serviceId = getServiceFromURI(currentUri, trackUri)
	updateServicesMetaDataKeys(serviceId, desc)
	statusString = ""
	if (service or "") ~= "" then
		statusString = statusString .. service
	end
	if (title ~= "") then
		if (statusString ~= "") then
			statusString = statusString .. ": "
		end
		statusString = statusString .. title
	end
	if (currentUri ~= nil and currentUri:find("x%-rincon%-stream:") == 1) then
		if (title2 == "" or title2 == " ") then
			title2 = "Line-In"
		end
		local zone = getZoneNameFromUUID(currentUri:match(".+:(.+)"))
		if (zone ~= nil) then
			title2 = title2 .. " (" .. zone .. ")"
		end
	end
	if (currentUri ~= nil and currentUri:find("x%-rincon:") == 1) then
		title2 = ""
		info = "Group"
		local zone = getZoneNameFromUUID(currentUri:match(".+:(.+)"))
		if (zone ~= nil) then
			info = info .. " driven by " .. zone
		end
	end
	if (currentUri == "") then
		info = "No music"
	end
	if (title ~= "" and title ~= title2 and string.sub(title2, 1, 10) == "x-sonosapi") then
		title2 = title
	end
	if (title2 ~= "" and title2 ~= title) then
		if (statusString ~= "") then
			statusString = statusString .. ": "
		end
		statusString = statusString .. title2
	end
	if (info ~= "") then
		if (statusString ~= "") then
			statusString = statusString .. ": "
		end
		statusString = statusString .. info
	end
	local dev = findDeviceByUUID( uuid ) or -1
	if albumArt ~= "" then
		local ip = getVar( "SonosIP", "", dev, SONOS_ZONE_SID )
		albumArt = url.absolute(string.format("http://%s:%s/", ip, port), albumArt)
	elseif serviceId then
		local ip = getVar( "SonosIP", "", dev, SONOS_ZONE_SID )
		albumArt = string.format("http://%s:%s/getaa?s=1&u=%s", ip, port, url.escape(currentUri))
	else
		albumArt = iconURL
	end
	return service, title, statusString, title2, artist, album, details, albumArt
end

local function parseSavedQueues(xml)
	local result = {}
	for id, title in xml:gmatch('<container%s?.-id="([^"]-)"[^>]->.-<dc:title%s?[^>]->(.-)</dc:title>.-</container>') do
		id = upnp.decode(id)
		title = upnp.decode(title)
		table.insert( result, id .. "@" .. title )
	end
	return table.concat( result, "\n" )
end

local function parseIdTitle(xml)
	local result = {}
	for id, title in xml:gmatch('<item%s?.-id="([^"]-)"[^>]->.-<dc:title%s?[^>]->(.-)</dc:title>.-</item>') do
		id = upnp.decode(id)
		title = upnp.decode(title)
		table.insert( result, id .. "@" .. title )
	end
	return table.concat( result, "\n" )
end

local function parseQueue(xml)
	local result = {}
	for title in xml:gmatch("<item%s?[^>]->.-<dc:title%s?[^>]->(.-)</dc:title>.-</item>") do
		title = upnp.decode(title)
		table.insert( result, title )
	end
	return table.concat( result, "\n" )
end

local setup -- forward declaration
-- refreshNow is the refresh handler for updateWithoutProxy (task). DO NOT call this function
-- directly. To get proper scheduling of refreshing, including on-demand refreshes, always
-- use updateNow()
local function refreshNow(uuid, force, refreshQueue)
	D("refreshNow(%1,%2,%3)", uuid, force, refreshQueue)
	if (uuid or "") == "" then
		return
	end
	local device = findDeviceByUUID( uuid )
	if not device then
		W("Can't refresh unknown zone %1; reload Luup to add this device.", uuid)
		return
	end

	if useProxy() and not force then
		D("refreshNow() proxy running, not forced; no update")
		return
	end

	if not ( isOnline(uuid) or setup(device, true) ) then
		D("refreshNow() zone is offline and cannot be started %1", uuid)
		return
	end

	local status, tmp
	local changed = false
	local statusString, info, title, title2, artist, album, details, albumArt
	local currentUri, currentUriMetaData, trackUri, trackUriMetaData, service

--[[
	-- PHR???
	local DeviceProperties = upnp.getService(uuid, UPNP_DEVICE_PROPERTIES_SERVICE)
	if DeviceProperties then
		status, tmp = DeviceProperties.GetZoneInfo({})
	else
		D("Can't find device properties service %1", UPNP_DEVICE_PROPERTIES_SERVICE)
	end
--]]

	if getVarNumeric( "MasterRole", 0, device, SONOS_ZONE_SID ) ~= 0 then
		D("refreshNow() zone is master role, fetching zone topology")
		updateZoneGroupTopology( uuid )
	end

	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if AVTransport then
		D("refreshNow() refreshing transport state")
		-- GetCurrentTransportState  (PLAYING, STOPPED, etc)
		status, tmp = AVTransport.GetTransportInfo({InstanceID="0"})
		if not status then
			commsFailure(device, tmp)
			return ""
		end

		-- Special handling TransportState: if now STOPPED, and TTS/alerts are playing, rush endSay
		changed = setData("TransportState", upnp.extractElement("CurrentTransportState", tmp, ""), uuid, changed)

		changed = setData("TransportStatus", upnp.extractElement("CurrentTransportStatus", tmp, ""), uuid, changed)
		changed = setData("TransportPlaySpeed", upnp.extractElement("CurrentSpeed", tmp, ""), uuid, changed)

		-- Get Playmode (NORMAL, REPEAT_ALL, SHUFFLE_NOREPEAT, SHUFFLE)
		_, tmp = AVTransport.GetTransportSettings({InstanceID="0"})
		changed = setData("CurrentPlayMode", upnp.extractElement("PlayMode", tmp, ""), uuid, changed)

		-- Get Crossfademode
		_, tmp = AVTransport.GetCrossfadeMode({InstanceID="0"})
		changed = setData("CurrentCrossfadeMode", upnp.extractElement("CrossfadeMode", tmp, ""), uuid, changed)

		-- Get Current Transport Actions (a CSV of valid Transport Action/Transitions)
		_, tmp = AVTransport.GetCurrentTransportActions({InstanceID="0"})
		changed = setData("CurrentTransportActions", upnp.extractElement("Actions", tmp, ""), uuid, changed)

		-- Get Media Information
		_, tmp = AVTransport.GetMediaInfo({InstanceID="0"})
		currentUri = upnp.extractElement("CurrentURI", tmp, "")
		currentUriMetaData = upnp.extractElement("CurrentURIMetaData", tmp, "")
		changed = setData("NumberOfTracks", upnp.extractElement("NrTracks", tmp, "NOT_IMPLEMENTED"), uuid, changed)
		changed = setData("CurrentMediaDuration", upnp.extractElement("MediaDuration", tmp, "NOT_IMPLEMENTED"), uuid, changed)
		changed = setData("AVTransportURI", currentUri, uuid, changed)
		changed = setData("AVTransportURIMetaData", currentUriMetaData, uuid, changed)

		-- Get Current URI - song or radio station etc
		_, tmp = AVTransport.GetPositionInfo({InstanceID="0"})
		trackUri = upnp.extractElement("TrackURI", tmp, "")
		trackUriMetaData = upnp.extractElement("TrackMetaData", tmp, "")
		changed = setData("CurrentTrack", upnp.extractElement("Track", tmp, "NOT_IMPLEMENTED"), uuid, changed)
		changed = setData("CurrentTrackDuration", upnp.extractElement("TrackDuration", tmp, "NOT_IMPLEMENTED"), uuid, changed)
		changed = setData("CurrentTrackURI", trackUri, uuid, changed)
		changed = setData("CurrentTrackMetaData", trackUriMetaData, uuid, changed)
		changed = setData("RelativeTimePosition", upnp.extractElement("RelTime", tmp, "NOT_IMPLEMENTED"), uuid, changed)

		service, title, statusString, title2, artist, album, details, albumArt =
			extractDataFromMetaData(uuid, currentUri, currentUriMetaData, trackUri, trackUriMetaData)

		changed = setData("CurrentService", service, uuid, changed)
		changed = setData("CurrentRadio", title, uuid, changed)
		changed = setData("CurrentStatus", statusString, uuid, changed)
		changed = setData("CurrentTitle", title2, uuid, changed)
		changed = setData("CurrentArtist", artist, uuid, changed)
		changed = setData("CurrentAlbum", album, uuid, changed)
		changed = setData("CurrentDetails", details, uuid, changed)
		changed = setData("CurrentAlbumArt", albumArt, uuid, changed)
	end

	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if Rendering then
		D("refreshNow() refreshing rendering state")
		-- Get Mute status
		status, tmp = Rendering.GetMute({OrderedArgs={"InstanceID=0", "Channel=Master"}})
		if not status then
			changed = setData("Mute", "", uuid, changed)
		else
			changed = setData("Mute", upnp.extractElement("CurrentMute", tmp, ""), uuid, changed)
		end

		-- Get Volume
		status, tmp = Rendering.GetVolume({OrderedArgs={"InstanceID=0", "Channel=Master"}})
		if not status then
			changed = setData("Volume", "", uuid, changed)
		else
			changed = setData("Volume", upnp.extractElement("CurrentVolume", tmp, ""), uuid, changed)
		end

		-- Get Bass
		status, tmp = Rendering.GetBass({OrderedArgs={"InstanceID=0", "Channel=Master"}})
		if not status then
			changed = setData("Bass", "", uuid, changed)
		else
			changed = setData("Bass", upnp.extractElement("CurrentBass", tmp, ""), uuid, changed)
		end

		-- Get Treble
		status, tmp = Rendering.GetTreble({OrderedArgs={"InstanceID=0", "Channel=Master"}})
		if not status then
			changed = setData("Treble", "", uuid, changed)
		else
			changed = setData("Treble", upnp.extractElement("CurrentTreble", tmp, ""), uuid, changed)
		end

		-- Get Loudness
		status, tmp = Rendering.GetLoudness({OrderedArgs={"InstanceID=0", "Channel=Master"}})
		if not status then
			changed = setData("Loudness", "", uuid, changed)
		else
			changed = setData("Loudness", upnp.extractElement("CurrentLoudness", tmp, ""), uuid, changed)
		end

		-- Get OutputFixed
		status, tmp = Rendering.GetOutputFixed({OrderedArgs={"InstanceID=0"}})
		if not status then
			changed = setData("OutputFixed", "0", uuid, changed)
		else
			changed = setData("OutputFixed", upnp.extractElement("CurrentFixed", tmp, ""), uuid, changed)
		end
	end

	-- Sonos queue
	if refreshQueue then
		D("refreshNow() refreshing queue")
		if (fetchQueue) then
			info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "Q:0", false, "dc:title", parseQueue, BROWSE_TIMEOUT)
		else
			info = ""
		end
		changed = setData("Queue", info, uuid, changed)
	end

	if changed then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), device)
	end
end

local function refreshVolumeNow(uuid, force)
	D("refreshVolumeNow(%1,%2)", uuid, force)

	if useProxy() and not force then
		return
	end
	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return false
	end

	local status, tmp, changed

	-- Get Volume
	status, tmp = Rendering.GetVolume({OrderedArgs={"InstanceID=0", "Channel=Master"}})

	if not status then
		commsFailure(findDeviceByUUID( uuid ), tmp)
		return
	end

	changed = setData("Volume", upnp.extractElement("CurrentVolume", tmp, ""), uuid, false)

	if changed and findDeviceByUUID( uuid ) then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), findDeviceByUUID( uuid ))
	end
end

local function refreshMuteNow(uuid, force)
	D("refreshMuteNow(%1)", uuid)

	if useProxy() and not force then
		return
	end
	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return
	end

	local status, tmp, changed

	-- Get Mute status
	status, tmp = Rendering.GetMute({OrderedArgs={"InstanceID=0", "Channel=Master"}})

	if not status then
		commsFailure(findDeviceByUUID( uuid ), tmp)
		return
	end

	changed = setData("Mute", upnp.extractElement("CurrentMute", tmp, ""), uuid, false)

	if changed and findDeviceByUUID( uuid ) then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), findDeviceByUUID( uuid ))
	end
end

local function updateWithoutProxy(task, device)
	D("updateWithoutProxy(%1,%2)", tostring(task), device)
	local uuid = findZoneByDevice( device )
	refreshNow(uuid, false, true)
	if not useProxy() then
		local ts = dataTable[uuid].TransportState or "STOPPED"
		local rp,rs = getVar("PollDelays", "15,60", device, SONOS_ZONE_SID):match( '^(%S+)%,%s*(.*)$' )
		rp = tonumber(rp) or 15
		rs = tonumber(rs) or 60
		-- Schedule next
		if not task then
			task = scheduler.getTask("update"..device)
		end
		if not task then
			task = scheduler.Task:new( "update"..device, device, updateWithoutProxy, { device } )
		end
		-- If player is stopped or is not group coordinator, use long delay.
		local dly = (ts == "STOPPED" or not isGroupCoordinator(uuid)) and rs or rp
		task:delay( dly )
		D("updateWithoutProxy() scheduled update for no proxy in state %1 delay %2", ts, dly)
		return
	else
		-- Not reschedulling, but leave task
		D("updateWithoutProxy() not rescheduling update, proxy running")
	end
	D("Proxy found, skipping poll reschedule")
end

local function updateNow( device )
	D("updateNow(%1)", device)
	if findZoneByDevice( device or -1 ) then
		local task = scheduler.getTask("update"..device) or scheduler.Task:new( "update"..device, device, updateWithoutProxy, { device } )
		task:delay(0, { replace=true } )
	end
end

local function controlAnotherZone(targetUUID, sourceUUID)
	D("controlAnotherZone(%1,%2)", targetUUID, sourceUUID)
	return targetUUID
end

-- Return dev,uuid for the group coordinator of the zone (which may be the zone itself).
local function controlByCoordinator(uuid)
	D("controlByCoordinator(%1)", uuid)
	if zoneInfo.zones[uuid].isSatellite then
		uuid = zoneInfo.zones[uuid].Base
	end
	local gr = getZoneGroup( uuid )
	if gr then
		uuid = gr.Coordinator or uuid
	end
	local dev = findDeviceByUUID( uuid )
	D("controlByCoordinator() coordinator %1 dev %2", uuid, dev)
	return dev, uuid
end

-- Decode special form URIs to Sonos' URIs with metadata.
local function decodeURI(localUUID, coordinator, uri)
	D("decodeURI(%1,%2,%3)", localUUID, coordinator, uri)
	local uuid
	local track = nil
	local uriMetaData = ""
	local serviceId
	local title = nil
	local controlByGroup = true
	local requireQueueing = false

	-- Handle URI shortcuts (plugin-specific, not Sonos)
	if uri:sub(1, 2) == "Q:" then
		-- Queue: Q: becomes x-rincon-queue:controllerUUID#0 plus possible seek for right song.
		track = uri:sub(3)
		uri = QUEUE_URI:format(coordinator)

	elseif uri:sub(1, 3) == "AI:" then
		-- Audio input: AI:zonename becomes x-rincon-stream:zoneUUID (if no zonename, current uuid)
		if #uri > 3 then
			uuid = getUUIDFromZoneName(uri:sub(4))
		else
			uuid = localUUID
		end
		uri = uuid and ( "x-rincon-stream:" .. uuid ) or nil

	elseif uri:sub(1, 3) == "SQ:" then
		-- Saved queue: SQ:Cubano becomes ID:savedqueueid
		-- Also allows SQ:12 if known
		local found = false
		title = uri:sub(4)
		local sq = getVar( "SavedQueues", "", pluginDevice, SONOS_SYS_SID )
		for line in sq:gmatch("([^\n]+)") do
			local id, t = line:match("^(.+)@(.-)$")
			if (id ~= nil and t == title) or id == uri then
				found = true
				uri = "ID:" .. id
				break
			end
		end
		if not found then
			W("Unable to resolve URI: saved queue %1 not found", title)
			uri = nil
		end

	elseif uri:sub(1, 3) == "FR:" then
		-- Favorite radio
		title = uri:sub(4)
		local found = false
		local ff = getVar( "FavoritesRadios", "", pluginDevice, SONOS_SYS_SID )
		for line in ff:gmatch("([^\n]+)") do
			local id, t = line:match("^(.+)@(.-)$")
			if id ~= nil and t == uri:sub(4) then
				found = true
				uri = "ID:" .. id
				break
			end
		end
		if not found then
			W("Unable to resolve URI: Favorite Radio %1 not found", title)
			uri = nil
		end

	elseif uri:sub(1, 3) == "SF:" then
		-- Favorite
		title = uri:sub(4)
		local found = false
		local ff = getVar( "Favorites", "", pluginDevice, SONOS_SYS_SID )
		for line in ff:gmatch("([^\n]+)") do
			local id, t = line:match("^(.+)@(.-)$")
			if (id ~= nil and t == uri:sub(4)) then
				found = true
				uri = "ID:" .. id
				break
			end
		end
		if not found then
			W("Unable to resolve URI: Favorite %1 not found", title)
			uri = nil
		end

	elseif uri:sub(1, 3) == "TR:" then
		-- TuneIn radio: TR:50486 becomes x-sonosapi-stream:s50486?sid=254&flags=32 + metadata
		title = uri:sub(4)
		serviceId = getSonosServiceId("TuneIn") or "254"
		uri = "x-sonosapi-stream:s" .. uri:sub(4) .. "?sid=" .. serviceId .. "&flags=32"

	elseif uri:sub(1, 3) == "SR:" then
		-- Sirius radio: SR:shade45 becomes x-sonosapi-hls:r%3ashade45?sid=37&flags=288 + metadata
		title = uri:sub(4)
		serviceId = getSonosServiceId("SiriusXM") or "37"
		uri = "x-sonosapi-hls:r%3a" .. title .. "?sid=" .. serviceId .. "&flags=288"

	elseif uri:sub(1, 3) == "GZ:" then
		-- Group to zone: GZ:controllername becomes x-rincon:controllerUUID
		controlByGroup = false
		local zone = uri:sub(4)
		if zone:match("^RINCON_%x+") then
			uuid = zone
		else
			uuid = getUUIDFromZoneName(zone)
		end
		uri = uuid and ( "x-rincon:" .. uuid ) or nil
	end

	D("decodeURI() uri now %1 title %2 track %3 serviceId %4", uri, title, track, serviceId)

	if uri then
		if uri:sub(1, 3) == "ID:" then
			local xml = upnp.browseContent(localUUID, UPNP_MR_CONTENT_DIRECTORY_SERVICE, uri:sub(4), true, nil, nil, nil)
			D("data from server:\r\n%1", xml)
			if xml == "" then
				uri = nil
			else
				title, uri = xml:match("<DIDL%-Lite%s?[^>]-><item%s?[^>]->.-<dc:title%s?[^>]->(.-)</dc:title>.-<res%s?[^>]->(.*)</res>.-</item></DIDL%-Lite>")
				if uri then
					uriMetaData = upnp.decode(xml:match("<DIDL%-Lite%s?[^>]-><item%s?[^>]->.-<r:resMD%s?[^>]->(.*)</r:resMD>.-</item></DIDL%-Lite>") or "")
				else
					title, uri = xml:match("<DIDL%-Lite%s?[^>]-><container%s?[^>]->.-<dc:title%s?[^>]->(.-)</dc:title>.-<res%s?[^>]->(.*)</res>.-</container></DIDL%-Lite>")
					if uri then
						uriMetaData = upnp.decode(xml:match("<DIDL%-Lite%s?[^>]-><container%s?[^>]->.-<r:resMD%s?[^>]->(.*)</r:resMD>.-</container></DIDL%-Lite>") or "")
					end
				end
			end
		end

		if uri:sub(1, 38) == "file:///jffs/settings/savedqueues.rsq#" or
				uri:sub(1, 18) == "x-rincon-playlist:" or
				uri:sub(1, 21) == "x-rincon-cpcontainer:" then
			requireQueueing = true
		end

		if uri ~= "" and uriMetaData == "" then
			-- Metadata still empty. Build it.
			_, serviceId = getServiceFromURI(uri, nil)
			D("decodeURI() url %1 serviceId %2 title %3", uri, serviceId, title)
			if serviceId and metaDataKeys[serviceId] ~= nil then
				if title == nil then
					uriMetaData = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
								  .. '<item><desc>' .. xmlescape(metaDataKeys[serviceId]) .. '</desc>'
								  .. '</item></DIDL-Lite>'
				else
					uriMetaData = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
								  .. '<item><dc:title>' .. xmlescape(title) .. '</dc:title>'
								  .. '<desc>' .. xmlescape(metaDataKeys[serviceId]) .. '</desc>'
								  .. '</item></DIDL-Lite>'
				end
			elseif title ~= nil then
				uriMetaData = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
							  .. '<item><dc:title>' .. xmlescape(title) .. '</dc:title>'
							  .. '<upnp:class>object.item.audioItem.audioBroadcast</upnp:class>'
							  .. '</item></DIDL-Lite>'
			end
		end
	end

	D("decodeURI() result uri=%1, meta=%2, track=%3, groupControl=%4, queueing=%5", uri, uriMetaData, track, controlByGroup, requireQueueing)
	return uri, uriMetaData, track, controlByGroup, requireQueueing
end

local groupDevices -- forward declaration
local function playURI(zoneUUID, instanceId, uri, speed, volume, uuids, sameVolumeForAll, enqueueMode, newGroup, controlByGroup)
	D("playURI(%1,%2,%3,%4,%5,%6,%7,%8,%9,%10)", zoneUUID, instanceId, uri, speed, volume, uuids, sameVolumeForAll, enqueueMode, newGroup, controlByGroup)
	uri = url.unescape(uri)

	local uriMetaData, track, controlByGroup2, requireQueueing, status, tmp, position
	local channel = "Master"

	if newGroup then
		controlByGroup = false
	end

	local uuid = zoneUUID
	local _,coordinator = controlByCoordinator( zoneUUID )
	if controlByGroup then
		uuid = coordinator
	end

	uri, uriMetaData, track, controlByGroup2, requireQueueing = decodeURI(uuid, coordinator, uri)
	if not uri then
		return false
	end
	if (controlByGroup and not controlByGroup2) then
		-- decodeURI override!
		controlByGroup = false -- luacheck: ignore 311
		uuid = zoneUUID
	end

	if requireQueueing and not enqueueMode then
		enqueueMode = "REPLACE_QUEUE_AND_PLAY"
	end
	local onlyEnqueue = ({ENQUEUE=true, REPLACE_ENQUEUE=true, ENQUEUE_AT_FIRST=true, ENQUEUE_AT_NEXT_PLAY=true})[(enqueueMode or ""):upper()] or false

	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)

	-- Queue management
	if AVTransport and enqueueMode
			 and (uri:sub(1, 12) == "x-file-cifs:"
					 or uri:sub(1, 37) == "file:///jffs/settings/savedqueues.rsq"
					 or uri:sub(1, 18) == "x-rincon-playlist:"
					 or uri:sub(1, 21) == "x-rincon-cpcontainer:") then
		if enqueueMode == "REPLACE_QUEUE" or enqueueMode == "REPLACE_QUEUE_AND_PLAY" then
			D("playURI() clearing queue")
			AVTransport.RemoveAllTracksFromQueue({InstanceID=instanceId})
		end

		if enqueueMode == "ENQUEUE_AT_FIRST" or enqueueMode == "ENQUEUE_AT_FIRST_AND_PLAY" then
			D("playURI() enqueueing at first")
			status, tmp = AVTransport.AddURIToQueue(
				 {OrderedArgs={"InstanceID=" .. instanceId,
							 "EnqueuedURI=" .. uri,
							 "EnqueuedURIMetaData=" .. uriMetaData,
							 "DesiredFirstTrackNumberEnqueued=1",
							 "EnqueueAsNext=false"}})
		elseif enqueueMode == "ENQUEUE_AT_NEXT_PLAY" then
			position = "0"
			status, tmp = AVTransport.GetMediaInfo({InstanceID="0"})
			if status and upnp.extractElement("CurrentURI", tmp, "") == QUEUE_URI:format(uuid) then
				status, tmp = AVTransport.GetPositionInfo({InstanceID="0"})
				if status then
					position = upnp.extractElement("Track", tmp, "")
					position = tonumber(position)+1
				end
			end
			D("playURI() enqueueing at "..position)
			status, tmp = AVTransport.AddURIToQueue(
				 {OrderedArgs={"InstanceID=" .. instanceId,
							 "EnqueuedURI=" .. uri,
							 "EnqueuedURIMetaData=" .. uriMetaData,
							 "DesiredFirstTrackNumberEnqueued=" .. position,
							 "EnqueueAsNext=false"}})
		elseif enqueueMode == "ENQUEUE" or enqueueMode == "ENQUEUE_AND_PLAY"
				or enqueueMode == "REPLACE_QUEUE" or enqueueMode == "REPLACE_QUEUE_AND_PLAY" then
			D("playURI() appending to queue")
			status, tmp = AVTransport.AddURIToQueue(
				 {OrderedArgs={"InstanceID=" .. instanceId,
							 "EnqueuedURI=" .. uri,
							 "EnqueuedURIMetaData=" .. uriMetaData,
							 "DesiredFirstTrackNumberEnqueued=0",
							 "EnqueueAsNext=true"}})
		else
			status = false
		end
		if status then
			track = upnp.extractElement("FirstTrackNumberEnqueued", tmp, "")
			uri = QUEUE_URI:format(uuid)
		else
			uri = nil
		end
	end

	if AVTransport and uri and not onlyEnqueue then
		if newGroup then
			D("playURI() creating new group")
			AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID=instanceId})

			-- If uuids is an array containing other than just the controlling device, group them.
			if uuids and not (#uuids == 1 and uuids[1] == uuid) then
				groupDevices(uuid, instanceId, uuids, sameVolumeForAll and volume or nil)
			end
		end

		D("playURI() setting URI to %1 meta %2", uri, uriMetaData)
		AVTransport.SetAVTransportURI(
			{OrderedArgs={"InstanceID=" .. instanceId,
							"CurrentURI=" .. uri,
							"CurrentURIMetaData=" .. uriMetaData}})

		if tonumber(track or "") then
			D("playURI() setting track %1", track)
			AVTransport.Seek(
				 {OrderedArgs={"InstanceID=" .. instanceId,
							 "Unit=TRACK_NR",
							 "Target=" .. track}})
		end

		if (volume or "") ~= "" then
			-- Don't attempt to set volume on fixed output volume zone.
			if tostring(dataTable[uuid].OutputFixed or 0) ~= "0" then
				-- Setting volume on fixed output device? If specific device, warn; otherwise quietly ignore.
				if not sameVolumeForAll then
					local device = findDeviceByUUID( uuid ) or -1
					W("(playURI) can't set volume on %1 (#%2) %3, configured for fixed output",
						(luup.devices[device] or {}).description, device, uuid)
				end
			elseif Rendering then
				D("playURI() setting volume %1", volume)
				Rendering.SetVolume(
					{OrderedArgs={"InstanceID=" .. instanceId,
								"Channel=" .. channel,
								"DesiredVolume=" .. volume}})
			end
		end

		speed = tonumber(speed) or 1
		D("playURI() starting play on %1 at speed %2", uuid, speed)
		AVTransport.Play(
			 {OrderedArgs={"InstanceID=" .. instanceId,
						 "Speed=" .. speed}})
	end

	return true
end

groupDevices = function(coordinator, instanceId, uuids, volume)
	D("groupDevices(%1,%2,%3,%4)", coordinator, instanceId, uuids, volume)
	for _,uuid in ipairs( uuids or {} ) do
		if uuid ~= coordinator then
			playURI(uuid, instanceId, "x-rincon:" .. coordinator, "1", volume, nil, false, nil, false, false)
		end
	end
end

local function savePlaybackContexts(device, uuids)
	D("savePlaybackContexts(%1,%2)", device, uuids)
	local cxt = {}
	for _,mz in ipairs( masterZones ) do
		local success,status = pcall( updateZoneGroupTopology, mz.uuid )
		if success and status then break end
	end
	for _,uuid in ipairs( uuids ) do
		if controlAnotherZone(uuid, findZoneByDevice( device ) ) then
			refreshNow(uuid, true, false)
			cxt[uuid] = {}
			cxt[uuid].TransportState = dataTable[uuid].TransportState
			cxt[uuid].TransportPlaySpeed = dataTable[uuid].TransportPlaySpeed
			cxt[uuid].CurrentPlayMode = dataTable[uuid].CurrentPlayMode
			cxt[uuid].CurrentCrossfadeMode = dataTable[uuid].CurrentCrossfadeMode
			cxt[uuid].CurrentTransportActions = dataTable[uuid].CurrentTransportActions
			cxt[uuid].AVTransportURI = dataTable[uuid].AVTransportURI
			cxt[uuid].AVTransportURIMetaData = dataTable[uuid].AVTransportURIMetaData
			cxt[uuid].CurrentTrack = dataTable[uuid].CurrentTrack
			cxt[uuid].CurrentTrackDuration = dataTable[uuid].CurrentTrackDuration
			cxt[uuid].RelativeTimePosition = dataTable[uuid].RelativeTimePosition
			cxt[uuid].Mute = dataTable[uuid].Mute
			cxt[uuid].Volume = dataTable[uuid].Volume
			cxt[uuid].GroupCoordinator = dataTable[uuid].GroupCoordinator
		end
	end

	return { context = cxt }
end

local function restorePlaybackContext(device, uuid, cxt)
	D("restorePlaybackContext(%1,%2,%3)", device, uuid, cxt)
	local instanceId="0"
	local channel="Master"

	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)

	if AVTransport then
		AVTransport.Stop({InstanceID=instanceId})

		AVTransport.SetAVTransportURI(
			{OrderedArgs={"InstanceID=" .. instanceId,
							"CurrentURI=" .. cxt.AVTransportURI,
							"CurrentURIMetaData=" .. cxt.AVTransportURIMetaData}})

		if (cxt.AVTransportURI ~= "") then
			if (cxt.CurrentTransportActions:find("Seek") ~= nil) then
				AVTransport.Seek(
					{OrderedArgs={"InstanceID=" .. instanceId,
									"Unit=TRACK_NR",
									"Target=" .. cxt.CurrentTrack}})

				if (cxt.CurrentTrackDuration ~= "0:00:00"
						and cxt.CurrentTrackDuration ~= "NOT_IMPLEMENTED"
						and cxt.RelativeTimePosition ~= "NOT_IMPLEMENTED") then
					AVTransport.Seek(
						{OrderedArgs={"InstanceID=" .. instanceId,
										"Unit=REL_TIME",
										"Target=" .. cxt.RelativeTimePosition}})
				end
			end

			-- Restore repeat, shuffle and cross fade mode only on the group coordinator
			if (cxt.GroupCoordinator == uuid) then
				AVTransport.SetPlayMode(
					{OrderedArgs={"InstanceID=" .. instanceId,
									"NewPlayMode=" .. cxt.CurrentPlayMode}})

				AVTransport.SetCrossfadeMode(
					{OrderedArgs={"InstanceID=" .. instanceId,
									"CrossfadeMode=" .. cxt.CurrentCrossfadeMode}})
			end
		end
	end

	if Rendering then
		Rendering.SetMute(
			{OrderedArgs={"InstanceID=" .. instanceId,
							"Channel=" .. channel,
							"DesiredMute=" .. cxt.Mute}})

		-- Don't set volume on fixed output device
		if tostring(dataTable[uuid].OutputFixed or 0) == "0" then
			Rendering.SetVolume(
				{OrderedArgs={"InstanceID=" .. instanceId,
								"Channel=" .. channel,
								"DesiredVolume=" .. cxt.Volume}})
		end
	end

	if (AVTransport ~= nil
			and cxt.AVTransportURI ~= ""
			and (cxt.TransportState == "PLAYING"
					 or cxt.TransportState == "TRANSITIONING")) then
		AVTransport.Play(
			{OrderedArgs={"InstanceID=" .. instanceId,
							"Speed=" .. cxt.TransportPlaySpeed}})
	end

	updateNow( device )
end

local function restorePlaybackContexts(device, playCxt)
	D("restorePlaybackContexts(%1,%2)", device, playCxt)
	-- local instanceId="0"
	-- local channel="Master"
	-- local localUUID = findZoneByDevice( device )
	-- local device2

	if not playCxt then
		-- W("Please save the context before restoring it!")
		return
	end

	-- Find coordinators and restore context
	for uuid, zone in pairs( playCxt.context ) do
		if zone.GroupCoordinator == uuid then
			restorePlaybackContext( findDeviceByUUID( uuid ) or 0, uuid, zone )
		end
	end

	-- Finally restore context for other zones -- ??? PHR do we need to? or is restoring coordinator sufficient? easy to test...
	for uuid, cxt in pairs(playCxt.context) do
		if cxt.GroupCoordinator ~= uuid then
			restorePlaybackContext( findDeviceByUUID( uuid ) or 0, uuid, cxt )
		end
	end
end

-- The device is added to the same group as target zone (UUID or name)
local function joinGroup(newMember, target)
	D("joinGroup(%1,%2)", newMember, target)
	local uuid = target:match("RINCON_%x+") and target or getUUIDFromZoneName(target)
	if uuid and zoneInfo.zones[uuid] and not zoneInfo.zones[uuid].isSatellite then
		local groupInfo = zoneInfo.groups[zoneInfo.zones[uuid].Group]
		D("joinGroup() group for %1 is %2", target, groupInfo)
		if groupInfo then
			for _,member in ipairs( groupInfo.members or {} ) do
				if member.UUID == newMember then return end -- already in group
			end
			D("joinGroup() adding %1 to group %2 coordinator %3", newMember, groupInfo.ID, groupInfo.Coordinator)
			playURI(newMember, "0", "x-rincon:" .. groupInfo.Coordinator, "1", nil, nil, false, nil, false, false)
		end
	end
end

-- Leave group. If zone is group coordinator, the group is dissolved.
local function leaveGroup(localUUID)
	D("leaveGroup(%1)", localUUID)
	local uuid = localUUID:match("RINCON_%x+") and localUUID or getUUIDFromZoneName(localUUID)
	if (zoneInfo.zones[uuid] or {}).isSatellite then return end
	local groupInfo = zoneInfo.groups[zoneInfo.zones[uuid].Group]
	if localUUID == groupInfo.Coordinator then
		D("leaveGroup() zone %1 is group coordinator; dissolving group")
		for _,member in ipairs( groupInfo.members or {} ) do
			if member.UUID ~= groupInfo.Coordinator then
				local AVTransport = upnp.getService(member.UUID, UPNP_AVTRANSPORT_SERVICE)
				if AVTransport then
					AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID="0"})
				end
			end
		end
	else
		local AVTransport = upnp.getService(localUUID, UPNP_AVTRANSPORT_SERVICE)
		if AVTransport then
			AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID="0"})
		end
	end
end

-- Update group members to be the set provided by "member", adding and removing as needed.
local function updateGroupMembers(gc, members)
	D("updateGroupMembers(%1,%2)", gc, members)
	local prevMembers, coordinator, grid = getGroupInfo(gc)
	D("updateGroupMembers() group coordinator %1 id %2 members %3", coordinator, grid, prevMembers)
	local targetMap = {}
	if members:upper() == "ALL" then
		local _, zones = getAllUUIDs()
		targetMap = map( zones )
	else
		for zone in members:gmatch("[^,]+") do
			local uuid
			if zone:match("RINCON_%x+") then
				uuid = zone
			else
				uuid = getUUIDFromZoneName(zone)
			end
			if ( uuid or "" ) ~= "" then
				targetMap[uuid] = true
			end
		end
	end
	targetMap[coordinator] = true -- GC must always be member of group, can't remove this way.

	-- Make any new members part of the group
	for uuid in pairs( targetMap ) do
		if not prevMembers:find(uuid) then
			D("updateGroupMembers() adding zone %1", uuid)
			playURI(uuid, "0", "x-rincon:" .. coordinator, "1", nil, nil, false, nil, false, false)
		end
	end

	-- Remove previous members that are no longer in group
	for uuid in prevMembers:gmatch("RINCON_%x+") do
		if not targetMap[uuid] then
			D("updateGroupMembers() removing %1", uuid)
			leaveGroup(uuid)
		end
	end
end

-- To pause all, find all the group coordinators, and tell them to stop.
local function pauseAll(device)
	D("pauseAll(%1)", device)
	local _, uuids = getAllUUIDs()
	local coords = {}
	for _,uuid in ipairs( uuids ) do
		local dev, gcr = controlByCoordinator( uuid )
		coords[gcr] = dev
	end
	for uuid in pairs( coords ) do
		local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
		if AVTransport then
			AVTransport.Pause({InstanceID="0"})
		end
	end
end

local function setupTTSSettings(device)
	D("setupTTSSettings(%1)", device)
	TTSConfig = nil
	if not tts then return end
	local s = getVar("TTSConfig", "", device, SONOS_SYS_SID)
	if s ~= "" then
		TTSConfig = json.decode( s )
	end
	if not TTSConfig then
		-- No TTS config; possible upgrade from 1.x
		local engine = getVar("DefaultEngineTTS", tts.getDefaultEngineId(), device, SONOS_SYS_SID)
		TTSConfig = { defaultengine=engine, engines={} }
	elseif not ( TTSConfig.defaultengine and tts.getEngine( TTSConfig.defaultengine ) ) then
		TTSConfig.defaultengine = tts.getDefaultEngineId()
	end
	if TTSConfig.version == nil then
		TTSConfig.version = 1
		TTSConfig.serial = 1
		TTSConfig.timestamp = os.time()
		setVar(SONOS_SYS_SID, "TTSConfig", json.encode( TTSConfig ), device)
	end

	-- NOTA BENE! TTSBaseURL must resolve to TTSBasePath in runtime! That is, whatever directory
	--            TTSBasePath points to must be the directory accessed via TTSBaseURL.
	-- On openLuup, TTS must be supported by Apache or similar external web server--openLuup's web
	-- server doesn't work (non-multitasking). The web server should alias a directory path into
	-- the openLuup runtime (or to wherever TTSBasePath points), and that alias should be used in
	-- TTSBaseURL. LocalIP must also be set to the IP address of the openLuup system (and cannot be
	-- localhost or 127.0.0.1).
	TTSBaseURL = getVar("TTSBaseURL", "", device, SONOS_SYS_SID, true)
	if "" == TTSBaseURL then
		TTSBaseURL = isOpenLuup and "/openluup/" or "/sonos/"
	end
	if TTSBaseURL:match( "^/" ) then -- not elseif!
		-- Expand directory only to full URL
		TTSBaseURL = string.format("http://%s:%d%s", VERA_LOCAL_IP, 80, TTSBaseURL)
	end
	TTSBasePath = getVar("TTSBasePath", "", device, SONOS_SYS_SID, true)
	if "" == TTSBasePath then
		TTSBasePath = isOpenLuup and getInstallPath() or "/www/sonos/"
	end
	D("setupTTSSettings() TTSBaseURL=%1; TTSBasePath=%2", TTSBaseURL, TTSBasePath)

	TTSChime = nil
	local installPath = getInstallPath()
	local chd = getVar( "TTSChime", "", device, SONOS_SYS_SID, true )
	if chd == "" then
		if not isOpenLuup then
			os.remove( "/www/sonos/Sonos_chime.mp3" )
			os.remove( "/www/sonos/Sonos_chime.wav" )
			os.remove( "/www/sonos/Sonos_chime.mp3.lzo" )
		end
		os.remove( installPath .. "Sonos_chime.mp3.lzo" )
		os.remove( installPath .. "Sonos_chime.wav" )
		os.remove( installPath .. "Sonos_chime.wav.lzo" )
		if not file_exists( installPath .. "Sonos_chime.mp3" ) then
			L("Downloading default chime MP3 sound")
			os.execute("curl -s -k -m 10 -o " .. Q( installPath, "Sonos_chime.mp3" ) ..
				" 'https://www.toggledbits.com/assets/sonos/Sonos_chime.mp3'")
		end
		if file_exists( installPath .. "Sonos_chime.mp3" ) then
			chd = "Sonos_chime.mp3,3"
		else
			L("Default chime Sonos_chime.mp3 not found; TTS chime disabled.")
		end
	end
	local chimefile, chimedur, chimevol = unpack( split( chd, "," ) )
	chimefile = chimefile or "" -- unpack returns empty array as nothing (no return values)
	D("setupTTSSettings() chime file %1 duration %2 from %3", chimefile, chimedur, chd)
	if chimefile == "0" or string.lower( chimefile ) == "none" or chimefile == "" then
		D("setupTTSSettings() chime suppressed by config")
	elseif file_exists( installPath .. chimefile ) then
		if TTSBasePath ~= installPath then
			D("setupTTSSettings() linking %1 to %2", installPath..chimefile, TTSBasePath..chimefile)
			os.remove( TTSBasePath .. chimefile )
			file_symlink( installPath .. chimefile, TTSBasePath .. chimefile )
		end
		TTSChime = { URI=TTSBaseURL..chimefile, Repeat=1 }
		TTSChime.URIMetadata = TTS_METADATA:format( "TTS Chime", "http-get:*:audio/mpeg:*", TTSChime.URI )
		TTSChime.Duration = tonumber( chimedur ) or 5
		TTSChime.Volume = tonumber( chimevol ) -- nil OK
	else
		W("The specified TTS chime file %1 does not exist", chimefile)
	end
	D("setupTTSSettings() TTSChime=%1", TTSChime)
end

local function getAvailableServices(uuid)
	D("getAvailableServices(%1)", uuid)
	local services = {}
	local MusicServices = upnp.getService(uuid, UPNP_MUSICSERVICES_SERVICE)
	if MusicServices == nil then
		return services
	end
	local tag = "Service"
	local status, tmp = MusicServices.ListAvailableServices({})
	if status == true then
		tmp = upnp.extractElement("AvailableServiceDescriptorList", tmp, "")
		for item in tmp:gmatch("(<"..tag.."%s.-</"..tag..">)") do
			local id = item:match("<"..tag..'%s?.-%sId="([^"]+)"[^>]->.-</'..tag..">")
			local name = item:match("<"..tag..'%s?.-%sName="([^"]+)"[^>]->.-</'..tag..">")
			if (id ~= nil and name ~= nil) then
				D("getAvailableServices() %1 => %2", id, name)
				services[id] = name
			end
		end
	end
	return services
end

-- Fix the locations of the legacy icons. This can eventually go away. 7.30: Or can it? :(
local function fixLegacyIcons()
	local basePath = getInstallPath()
	local f = io.open( basePath .. "Sonos.png", "rb" )
	if not f then
		local _,m = pcall( require, "mime" )
		if not package.loaded.mime then L{level=2,msg="System package 'mime' needed but could not be loaded."} return end
		f = io.open( basePath .. "Sonos.png", "wb" )
		-- NB: mime.unb64 returns two values; we only want one.
		f:write( ( m.unb64([[iVBORw0KGgoAAAANSUhEUgAAADwAAAA8CAIAAAC1nk4lAAAAAXNSR0IArs4c6QAAAARnQU1BAACx
jwv8YQUAAAAJcEhZcwAADsIAAA7CARUoSoAAAANrSURBVGhD7ZpLKLxRGMbPjEH9yYosSIqUy0LZ
YIlm3FYu2cjCpWxdc6lhxKTZEFE2SHKJhUuJFAvXKOUeKQszuUwRueTuad5jmlxm9F8cps5v873v
c84333POd95T52sUr6+vzNlQ8qtTIU2LwilNfyxEnU7Ho79ETU0Njyx8Ydrf3z84OJjnv83BwYHR
aPxgmsG0LbW1tZOTkzz5A8AMLPHkHVmIopCmRSFNi0KaFoU0LQppWhTStCikaVFI06L4ken19fWW
lpa+vr7r62suMYZ4YGCgubl5YmLi6emJq4yZzWYeWeL9/X2eMHZ3dzc8PNzU1DQ2Nvbw8MBVxs7P
zzs7O9va2mw728Gx6YWFhYKCgtvb28XFxfb2dhIPDw8TExPn5+eVSmVPT09WVpZ1POXl5RsbGxQv
LS11dHRQbDKZkpOTp6enVSrV0NBQWlraxcUFdLjPyMjY3NxEWl1dfXNzQ/3twc+K73w+2DY2NhoM
Bp68A5ddXV0Uv7y8lJSU1NfXU5qenh4ZGQnfiEdHR4uLi0nPzc1tbW2lGGi12oqKCgR7e3uxsbHP
z8+kf+A/D7apqamDg4NlZWWYNlIuLy8xMdnZ2ZQqFIq8vLyZmRlKQU5OTn5+/vb2Ns8Ze3x8xBtD
N54zhg50S1BQUEBAAIba39+P90mt9nFsOjw8HMPFT1dWVlZVVUGBS2qyAgUTwBPG4uPjGxoaYHFn
Z4dLn7De4uLi0tvbixWIlZOUlGRbEt/xo0L09vYuLCwcHx9HGd3f33t5eUVERKAuqRXPRhnFxcVR
SiQkJNTV1XV3d1Pq6uqKNWBNge0t8I3lDiUsLGx2dpZEO6j49XuMRmNRUVFMTMzu7m5UVJS7uztE
vV6PNbC2thYSEoJyxLaAcqT+VtRqNfYWqwmdTocVtbW1hVe3srJydnaGCaYmrPt/FlZXV0tLS0m0
wxefxaKjozUaDc8tLC8vz83N+fj4ZGZmenh4kHh1dYWd6/j4ODQ0FDsJ9gTSYSswMNDT05PS09NT
X19firHD4HUdHR1hqJhaNzc30k9OTkZGRjDylJQUNJFITE1N4enys9gvIU2LQpoWhTQtCmlaFNK0
KKRpUUjTopCmReGUpr84I+Is6Ofnx/PfxmQymc1mx//34NFfwoFpp0AWoiikaTEw9galFENnD/Sm
4wAAAABJRU5ErkJggg==]]) ) )
	end
	f:close()

	-- Apparently as of 7.30, this is new designated location.
	if not ( isOpenLuup or file_exists( "/www/cmh/skins/default/icons/Sonos.png" ) ) then
		os.execute( "mkdir -p /www/cmh/skins/default/icons/" )
		file_symlink( basePath.."Sonos.png", "/www/cmh/skins/default/icons/Sonos.png" )
	end
end

-- Set up custom icon for device. The icon is retrieved from the device
-- itself to a local copy, then a custom static JSON file is generated and
-- assigned to the device.
local function setDeviceIcon( device, icon, model, uuid )
	-- Set up local copy of icon from device and static JSON pointing to it
	-- (so icon works both locally and remote)
	local ICONREV = 19345
	local icorev = getVarNumeric("_icorev", 0, device, SONOS_ZONE_SID)
	local installPath = getInstallPath()
	local iconPath, iconURL
	if isOpenLuup then
		iconPath = installPath
		iconURL = "http://" .. VERA_LOCAL_IP .. ":3480/%s"
	else
		-- Vera Luup
		iconPath = "/www/cmh/skins/default/icons/"
		iconURL = "../../../icons/%s" -- blech. c'mon guys, really.
	end
	-- See if there's a local copy of the custom icon
	local iconFile = string.format( "Sonos_%s%s", model, icon:match( "[^/]+$" ):match( "%..+$" ) )
	if icorev < ICONREV or not file_exists( installPath..iconFile ) then
		L("Fetching custom device icon from %1 to %2 as %3", icon, installPath, iconFile )
		os.execute( "curl -s -m 10 -o " .. Q( installPath, iconFile ) .. " " .. Q( icon ) )
	end
	if installPath ~= iconPath then
		os.execute( "ln -sf " .. Q(installPath, iconFile) .. " " .. Q(iconPath) )
	end
	-- See if we've already created a custom static JSON for this UUID or model.
	local staticJSONFile
	if ( uuid or "") ~= "" then
		staticJSONFile = string.format( "D_Sonos1_%s.json", ( tostring( uuid ):lower():gsub( "[^a-z0-9_]", "_" ) ) )
		if file_exists_LZO( installPath .. staticJSONFile ) then
			L("Using device-specific UI %s", staticJSONFile )
		else
			staticJSONFile = nil
		end
	end
	if not staticJSONFile then
		staticJSONFile = string.format( "D_Sonos1_%s.json", ( tostring( model or "GENERIC" ):upper():gsub( "[^A-Z0-9_]", "_" ) ) )
	end
	if icorev < ICONREV or not file_exists_LZO( installPath .. staticJSONFile ) then
		-- Create model-specific version of static JSON
		L("Creating custom static JSON (device UI) in %1", staticJSONFile)
		local s,f = file_exists( installPath.."D_Sonos1.json", true )
		if not s then
			os.execute( 'pluto-lzo d ' .. Q(installPath, 'D_Sonos1.json.lzo') .. ' /tmp/D_Sonos1.json.tmp' )
			f = io.open( '/tmp/D_Sonos1.json.tmp', 'r' )
			if not f then
				W("Failed to open /tmp/D_Sonos1.json.tmp")
				staticJSONFile = nil
			end
		end
		if f then -- explicit, two paths above
			-- Read default static JSON
			s = f:read("*a")
			f:close()
			local d = json.decode( s )
			if not d then error "Can't parse generic static JSON file" end
			-- Modify to new icon in default path
			local ist = iconURL:format( iconFile )
			D( "Creating static JSON for icon %1", ist )
			d.default_icon = ist
			d.flashicon = nil
			-- d.state_icons = nil
			d._comment = { "AUTOMATICALLY GENERATED -- DO NOT MODIFY THIS FILE (rev " .. ICONREV .. ")" }
			-- Save custom.
			f = io.open( installPath .. staticJSONFile, "w" )
			if not f then
				E("can't write %1 in %2", staticJSONFile, installPath)
				staticJSONFile = nil
			else
				f:write( json.encode( d, { indent=4, keyorder={ "_comment", "default_icon" } } ) )
				f:close()
			end
		end
	end
	-- Is this device using the right static JSON file?
	local cj = luup.attr_get( 'device_json', device ) or ""
	if not staticJSONFile then staticJSONFile = "D_Sonos1.json" end -- for safety
	if cj ~= staticJSONFile or icorev < ICONREV then
		-- No. Switch it out.
		W("Device device_json currently %1, swapping to %2 (and reloading)", cj, staticJSONFile )
		luup.attr_set( 'device_json', staticJSONFile, device )
		-- rigpapa: by using a delay here, we increase the chances that changes for multiple
		-- players can be captured in one reload, rather than one per.
		local t = scheduler.getTask("reload")
		if not t then
			t = scheduler.Task:new("reload", device, SonosReload)
		end
		t:delay( 15, { replace=true } )
	end
	setVar( SONOS_ZONE_SID, "_icorev", ICONREV, device )
end

local function getCheckStateRate(device)
	return getVarNumeric("CheckStateRate", 0, device, SONOS_ZONE_SID) * 60
end

function checkDeviceState(task, device)
	D("checkDeviceState(%1,%2)", tostring(task), device)
	local rate = getCheckStateRate(device)
	if rate > 0 then
		task:delay( rate )
		setup(device, false)
	else
		task:close()
	end
end

local function setCheckStateRate(device, rate)
	D("setCheckStateRate(%1,%2)", device, rate)
	if tonumber(rate) == nil then rate = 0 end
	setVar(SONOS_ZONE_SID, "CheckStateRate", rate, device)

	idConfRefresh = idConfRefresh + 1

	checkDeviceState(idConfRefresh .. ":" .. device)
end

local function handleRenderingChange(uuid, event)
	-- D("handleRenderingChange(%1,%2)", uuid, event)
	D("handleRenderingChange(%1, event)", uuid)
	local changed = false
	local tmp = event:match("<Event%s?[^>]-><InstanceID%s?[^>]->(.+)</InstanceID></Event>")
	if tmp ~= nil then
		for token, attributes in tmp:gmatch('<([a-zA-Z0-9:]+)(%s?.-)/>') do
			local attrTable = {}
			for attr, value in attributes:gmatch('%s(.-)="(.-)"') do
				attrTable[attr] = value
			end
			if (attrTable.val ~= nil and
					(attrTable.channel == "Master" or attrTable.channel == nil)) then
				changed = setData(token, upnp.decode(attrTable.val), uuid, changed)
			end
		end
	end
	if changed and findDeviceByUUID( uuid ) then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), findDeviceByUUID( uuid ) or -1)
	end
end

local function handleAVTransportChange(uuid, event)
	-- D("handleAVTransportChange(%1,%2)", uuid, event)
	D("handleAVTransportChange(%1, event)", uuid)
	local statusString, title, title2, artist, album, details, albumArt, desc
	local currentUri, currentUriMetaData, trackUri, trackUriMetaData, service, serviceId
	local changed = false
	local tmp = event:match("<Event%s?[^>]-><InstanceID%s?[^>]->(.+)</InstanceID></Event>")
	if tmp ~= nil then
		local found = false
		local found2 = false
		for token, attributes in tmp:gmatch('<([a-zA-Z0-9:]+)(%s?.-)/>') do
			if (token == "RelativeTimePosition") then
				found = true
			elseif (token == "r:EnqueuedTransportURIMetaData") then
				found2 = true
			end
			local attrTable = {}
			for attr, value in attributes:gmatch('%s(.-)="(.-)"') do
				attrTable[attr] = value
			end
			if (attrTable.val ~= nil) then
				-- Special handling for TransportState/TTS interaction (see also below)
				local vchanged = setData(token, upnp.decode(attrTable.val), uuid, false)
				changed = vchanged or changed
			end
		end

		currentUri = dataTable[uuid].AVTransportURI
		currentUriMetaData = dataTable[uuid].AVTransportURIMetaData
		trackUri = dataTable[uuid].CurrentTrackURI
		trackUriMetaData = dataTable[uuid].CurrentTrackMetaData
		service, title, statusString, title2, artist, album, details, albumArt =
			extractDataFromMetaData(uuid, currentUri, currentUriMetaData, trackUri, trackUriMetaData)
		changed = setData("CurrentService", service, uuid, changed)
		changed = setData("CurrentRadio", title, uuid, changed)
		changed = setData("CurrentStatus", statusString, uuid, changed)
		changed = setData("CurrentTitle", title2, uuid, changed)
		changed = setData("CurrentArtist", artist, uuid, changed)
		changed = setData("CurrentAlbum", album, uuid, changed)
		changed = setData("CurrentDetails", details, uuid, changed)
		changed = setData("CurrentAlbumArt", albumArt, uuid, changed)

		if not found then
			local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
			if AVTransport ~= nil then
				local _, tmp2 = AVTransport.GetPositionInfo({InstanceID="0"})
				changed = setData("RelativeTimePosition", upnp.extractElement("RelTime", tmp2, "NOT_IMPLEMENTED"), uuid, changed)
			end
		end

		if found2 then
			_, title, artist, album, details, albumArt, desc = -- luacheck: ignore 311
				getSimpleDIDLStatus(dataTable[uuid]["r:EnqueuedTransportURIMetaData"])
			_, serviceId = getServiceFromURI(currentUri, trackUri)
			updateServicesMetaDataKeys(serviceId, desc)
		end
	end
	if changed and findDeviceByUUID( uuid ) then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), findDeviceByUUID( uuid ))
	end
end

local function handleContentDirectoryChange(device, uuid, id)
	D("handleContentDirectoryChange(%1,%2,%3)", device, uuid, id)
	local info
	local changed = false

	if (id:find("SQ:,") == 1) then
		-- Sonos playlists
		info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "SQ:", false, "dc:title", parseSavedQueues, BROWSE_TIMEOUT)
		setVar( SONOS_SYS_SID, "SavedQueues", info, pluginDevice )
	elseif (id:find("R:0,") == 1) then
		-- Favorites radio stations
		info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "R:0/0", false, "dc:title", parseIdTitle, BROWSE_TIMEOUT)
		setVar( SONOS_SYS_SID, "FavoritesRadios", info, pluginDevice )
	elseif (id:find("FV:2,") == 1) then
		-- Sonos favorites
		info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "FV:2", false, "dc:title", parseIdTitle, BROWSE_TIMEOUT)
		setVar( SONOS_SYS_SID, "Favorites", info, pluginDevice )
	elseif (id:find("Q:0,") == 1) then
		-- Sonos queue
		if (fetchQueue) then
			info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "Q:0", false, "dc:title", parseQueue, BROWSE_TIMEOUT)
		else
			info = ""
		end
		changed = setData("Queue", info, uuid, changed)
	end
	if changed then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), device)
	end
end

-- N.B. called via call_delay from L_SonosUPnP
function processProxySubscriptions(info)
	D("processProxySubscriptions() processing UPnP Event Proxy subscriptions: %1 (pass-thru)", info)
	upnp.processProxySubscriptions()
end

-- N.B. called via call_delay from L_SonosUPnP
function renewSubscriptions(data)
	D("renewSubscriptions(%1)", data)
	local device, uuid = data:match("(%d+):(.*)")
	device = tonumber(device)
	if device and uuid then
		if uuid ~= findZoneByDevice( device )  then
			D("renewSubscriptions() ignored for uuid %1 (device %2/UUID mismatch, got %3)", uuid, device, findZoneByDevice( device ))
			EventSubscriptions[uuid] = nil
		elseif (zoneInfo.zones[uuid] or {}).isSatellite then
			D("renewSubscriptions() skipped for %1, now identified as Satellite", uuid)
			EventSubscriptions[uuid] = nil
		else
			-- Attempt renewal.
			upnp.subscribeToEvents(device, VERA_IP, EventSubscriptions[uuid], SONOS_ZONE_SID, uuid)
			local retry = false
			for _,sub in ipairs(EventSubscriptions[uuid]) do
				D("renewSubscriptions() %1 event service %2 subscription sid %3 expiry %4 error %5",
					uuid, sub.service, sub.id, sub.expiry, sub.error)
				if ( sub.id or "" ) == "" or sub.error then
					retry = true
				end
			end
			if retry then
				D("renewSubscriptions() one or more renewals failed; retrying")
				local _,nsub = upnp.subscribeToEvents(device, VERA_IP, EventSubscriptions[uuid], SONOS_ZONE_SID, uuid)
				if nsub == 0 then
					-- Worst-case scenario--maybe proxy went away?
					W("All event renewals failed for #%1; did proxy go away? Checking...", device)
					EventSubscriptions[uuid] = nil
					local t = scheduler.getTask( "checkProxy" )
					t:delay( 0 )
				end
			end
		end
	end
end

-- N.B. called via call_delay from L_SonosUPnP
function cancelProxySubscription(sid)
	D("cancelProxySubscription(%1) pass-thru", sid)
	upnp.cancelProxySubscription(sid)
end

local function setDebugLogs(val)
	D("setDebugLogs(%1)", val)
	DEBUG_MODE = (val % 2) ~= 0
	if upnp then upnp.DEBUG_MODE = (math.floor( val / 2 ) % 2) ~= 0 end
	if tts then tts.DEBUG_MODE = (math.floor( val / 4 ) % 2) ~= 0 end
end

local function setReadQueueContent(device, enable)
	D("setReadQueueContent(%1,%2)", device, enable)

	if ((enable == "true") or (enable == "yes"))
	then
		enable = "1"
	elseif ((enable == "false") or (enable == "no"))
	then
		enable = "0"
	end
	if ((enable ~= "0") and (enable ~= "1"))
	then
		luupTask("SetReadQueueContent: invalid argument", TASK_ERROR)
		return
	end

	setVar(SONOS_SYS_SID, "FetchQueue", enable, pluginDevice)
	if (enable == "1")
	then
		fetchQueue = true
	else
		fetchQueue = false
	end
	handleContentDirectoryChange(device, findZoneByDevice( device ), "Q:0,")
end

-- Check that the proxy is running.
function checkProxy( task, device )
	D("checkProxy(%1,%2)", tostring(task), device)
	local version = upnp.getProxyApiVersion()
	local proxy = version ~= nil and version
	if proxy then
		L("UPnP Event Proxy identified - API version %1", version)
	else
		W("UPnP Event Proxy plugin could not be contacted; polling for status will be used. This is inefficient; please consider installing the plugin from the marketplace.")
		upnp.unuseProxy()
		-- Kick update threads on all zone devices if they are not currently scheduled.
		for _,zdev in pairs( Zones ) do
			local t = scheduler.getTask( "update"..zdev ) or
				scheduler.Task:new( "update"..zdev, zdev, updateWithoutProxy, { zdev } )
			if t:suspended() then t:delay( 0 ) end -- run immediately
		end
		-- Fall through to check again, in case it starts up. We only get to here if the proxy was
		-- working at startup, so it could theoretically be restored (and that's better than polling).
	end
	task:delay(300)
end

setup = function(zoneDevice, flag)
	D("setup(%1,%2)", zoneDevice, flag)

	if getVarNumeric( "Enabled", 1, pluginDevice, SONOS_SYS_SID ) == 0 then
		E("Can't start #%1; plugin is disabled", zoneDevice)
		deviceIsOffline( zoneDevice )
		return false
	end

	local uuid = luup.attr_get( "altid", zoneDevice ) or error("Invalid UUID on device "..zoneDevice) -- "shouldn't happen"
	D("setup() uuid %1 device %2", uuid, luup.devices[zoneDevice])
	upnp.resetServices( uuid )
	if EventSubscriptions[uuid] then
		upnp.cancelProxySubscriptions(EventSubscriptions)
		EventSubscriptions[uuid] = nil
	end
	dataTable[uuid] = nil

	local newIP = getIPFromUUID( uuid )
	local oldIP = getVar( "SonosIP", "", zoneDevice, SONOS_ZONE_SID )
	D("setup() new IP %1 old %2", newIP, oldIP)
	if (newIP or "") == "" then
		-- Zone not currently in zone info (may be offline); use last known
		newIP = oldIP
	elseif newIP ~= oldIP then
		-- Update last known
		luup.attr_set( "mac", "", zoneDevice )
		luup.attr_set( "ip", "", zoneDevice )
		setVar( SONOS_ZONE_SID, "SonosIP", newIP, zoneDevice )
	end
	if (newIP or "") == "" then
		setVar(SONOS_ZONE_SID, "SonosOnline", "0", zoneDevice)
		setVar(UPNP_AVTRANSPORT_SID, "CurrentStatus", "Offline", zoneDevice)
		setVar(SONOS_ZONE_SID, "ProxyUsed", "", zoneDevice) -- plugin variable??? different per zone?
		E("No/invalid current IP address for #%1", zoneDevice)
		return false
	end

	local descrURL = string.format(descriptionURL, newIP, port)
	local status, _, values, icon =
							 upnp.setup(descrURL,
										"urn:schemas-upnp-org:device:ZonePlayer:1",
										{ "UDN", "roomName", "modelName", "modelNumber" },
										{ { "urn:schemas-upnp-org:device:ZonePlayer:1",
											{ UPNP_MUSICSERVICES_SERVICE,
											UPNP_DEVICE_PROPERTIES_SERVICE,
											UPNP_ZONEGROUPTOPOLOGY_SERVICE } },
										{ "urn:schemas-upnp-org:device:MediaRenderer:1",
											{ UPNP_AVTRANSPORT_SERVICE,
											UPNP_RENDERING_CONTROL_SERVICE,
											UPNP_GROUP_RENDERING_CONTROL_SERVICE } },
										{ "urn:schemas-upnp-org:device:MediaServer:1",
											{ UPNP_MR_CONTENT_DIRECTORY_SERVICE } }})
	if status then
		local newuuid = values.UDN:match("uuid:(.+)") or ""
		if uuid ~= newuuid then
			W("Zone %1 (#%2) uuid changed from %3 to %4; offline", (luup.devices[zoneDevice] or {}).description,
				zoneDevice, uuid, newuuid)
			status = false
		end
	end
	if not status then -- N.B. not else!
		E("Zone %1 (#%2) appears to be offline. %3", (luup.devices[zoneDevice] or {}).description,
			zoneDevice, uuid)
		deviceIsOffline( zoneDevice )
		return false
	end

	-- Mark online
	dataTable[uuid] = {}

	deviceIsOnline(zoneDevice)

	local changed = setData("CurrentStatus", "Online", uuid, false)

	-- Subscribe to service notifications from proxy. If we know ourselves to be a satellite at
	-- this point, don't.
	local isSatellite = (((zoneInfo or {}).zones or {})[uuid] or {}).isSatellite
	if status and not isSatellite then
		if useProxy() then
			-- Create subscription lists from templates. Deep copies because the subscriber modifies
			-- them per zone/uuid. Non-master don't subscribe to topology or content updates.
			EventSubscriptions[uuid] = {}
			for _,v in ipairs( ZoneSubscriptionsTemplate ) do
				table.insert( EventSubscriptions[uuid], deepCopy( v ) )
			end
			if getVarNumeric( "MasterRole", 0, zoneDevice, SONOS_ZONE_SID ) ~= 0 then
				for _,v in ipairs( MasterSubscriptionsTemplate ) do
					table.insert( EventSubscriptions[uuid], deepCopy( v ) )
				end
			end
			upnp.subscribeToEvents(zoneDevice, VERA_IP, EventSubscriptions[uuid], SONOS_ZONE_SID, uuid)
			if DEBUG_MODE then
				for _,sub in ipairs(EventSubscriptions[uuid]) do
					D("setup() %1 event service %2 subscription sid %3 expiry %4", uuid, sub.service, sub.id, sub.expiry)
				end
			end

			setVar(SONOS_SYS_SID, "ProxyUsed", "proxy is in use", zoneDevice)
			BROWSE_TIMEOUT = 30
		else
			setVar(SONOS_SYS_SID, "ProxyUsed", "proxy is not in use", zoneDevice)
			BROWSE_TIMEOUT = 5
		end
	end

	changed = setData("SonosID", uuid, uuid, changed)
	local roomName = upnp.decode( values.roomName or "" )
	changed = setData("ZoneName", roomName or "", uuid, changed)
	local modelName = upnp.decode( values.modelName or "" )
	changed = setData("SonosModelName", modelName, uuid, changed)
	changed = setData("SonosModelNumber", values.modelNumber or "", uuid, changed)
	local model = 0
	if (values.modelNumber == "S3") then
		model = 1
	elseif (values.modelNumber == "S5") then
		model = 2
	elseif (values.modelNumber == "ZP80") then
		model = 3
	elseif (values.modelNumber == "ZP90") then
		model = 3
	elseif (values.modelNumber == "ZP100") then
		model = 4
	elseif (values.modelNumber == "ZP120") then
		model = 4
	elseif (values.modelNumber == "S9") then
		model = 5
	elseif (values.modelNumber == "S1") then
		model = 6
	elseif values.modelNumber == "S22" then
		model = 7 -- 2019-01-25 One SL gen 2
	elseif values.modelNumber == "S12" then
		-- Newer hardware revision of Play 1
		model = 6 -- 2019-07-05 rigpapa; from @cranb https://community.getvera.com/t/version-1-4-3-development/209171/11
	end
	changed = setData("SonosModel", tostring(model), uuid, changed)

	L("Device #%1 at %2 is %3 (%4) uuid %5",
		zoneDevice,
		tostring( newIP ),
		tostring( modelName ),
		tostring( values.modelNumber ),
		tostring( uuid )
	)

	-- Use pcall so any issue setting up icon does not interfere with initialization and operation
	pcall( setDeviceIcon, zoneDevice, icon, values.modelNumber, uuid )

	if getVarNumeric( "MasterRole", 0, zoneDevice, SONOS_ZONE_SID ) ~= 0 then
		-- Master role zone. Fetch topology, services and content directories.
		updateZoneGroupTopology( uuid )

		if not sonosServices then
			sonosServices = getAvailableServices(uuid)
		end

		-- Sonos playlists
		local info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "SQ:", false,
			"dc:title", parseSavedQueues, BROWSE_TIMEOUT)
		setVar( SONOS_SYS_SID, "SavedQueues", info, pluginDevice )

		-- Favorites radio stations
		info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "R:0/0", false,
			"dc:title", parseIdTitle, BROWSE_TIMEOUT)
		setVar( SONOS_SYS_SID, "FavoritesRadios", info, pluginDevice )

		-- Sonos favorites
		info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "FV:2", false,
			"dc:title", parseIdTitle, BROWSE_TIMEOUT)
		setVar( SONOS_SYS_SID, "Favorites", info, pluginDevice )
	end

	if changed then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), zoneDevice)
	end

	local rate = getCheckStateRate(zoneDevice) -- ???
	if rate > 0 then
		local t = scheduler.getTask("checkState"..zoneDevice) or
			scheduler.Task:new("checkState"..zoneDevice, zoneDevice, checkDeviceState, { zoneDevice } )
		t:delay( rate, { replace=true } )
	end

	updateNow( zoneDevice )

	return true
end

local function zoneRunOnce( dev )
	local s = getVarNumeric( "ConfigVersion", 0, dev, SONOS_SYS_SID ) -- yes, SYS
	if s == 0 then
		-- New zone device
		initVar( "SonosID", "", dev, UPNP_DEVICE_PROPERTIES_SID )
		initVar( "SonosOnline", "0", dev, SONOS_ZONE_SID )
		initVar( "PollDelays", "15,60", dev, SONOS_ZONE_SID )
	end

	initVar( "DesignatedMaster", "", dev, SONOS_ZONE_SID )

	if DEVELOPMENT or s < 20103 then
		deleteVar( SONOS_ZONE_SID, "PluginVersion", dev )
		deleteVar( SONOS_ZONE_SID, "RouterIp", dev )
		deleteVar( SONOS_ZONE_SID, "RouterPort", dev )
		deleteVar( SONOS_ZONE_SID, "CheckStateRate", dev )
		deleteVar( SONOS_ZONE_SID, "DebugLogs", dev )
		deleteVar( SONOS_ZONE_SID, "FetchQueue", dev )
		deleteVar( SONOS_ZONE_SID, "DiscoveryPatchInstalled", dev )
		deleteVar( SONOS_ZONE_SID, "DiscoveryResult", dev )
		deleteVar( SONOS_ZONE_SID, "ProxyUsed", dev )
		deleteVar( SONOS_ZONE_SID, "MaryTTSServerURL", dev )
		deleteVar( SONOS_ZONE_SID, "MicrosoftClientId", dev )
		deleteVar( SONOS_ZONE_SID, "MicrosoftClientSecret", dev )
		deleteVar( UPNP_MR_CONTENT_DIRECTORY_SID, "SavedQueues", dev )
		deleteVar( UPNP_MR_CONTENT_DIRECTORY_SID, "Favorites", dev )
		deleteVar( UPNP_MR_CONTENT_DIRECTORY_SID, "FavoritesRadios", dev )
		deleteVar( UPNP_ZONEGROUPTOPOLOGY_SID, "ZoneGroupState", dev )
		deleteVar( SONOS_ZONE_SID, "SonosServicesKeys", dev )
		deleteVar( SONOS_ZONE_SID, "DefaultLanguageTTS", dev )
		deleteVar( SONOS_ZONE_SID, "DefaultEngineTTS", dev )
		deleteVar( SONOS_ZONE_SID, "GoogleTTSServerURL", dev )
		deleteVar( SONOS_ZONE_SID, "OSXTTSServerURL", dev )
		deleteVar( SONOS_ZONE_SID, "ResponsiveVoiceTTSServerURL", dev )
		deleteVar( SONOS_ZONE_SID, "TTSBasePath", dev )
		deleteVar( SONOS_ZONE_SID, "TTSBaseURL", dev )
		deleteVar( SONOS_ZONE_SID, "TTSRate", dev )
		deleteVar( SONOS_ZONE_SID, "TTSPitch", dev )
		deleteVar( SONOS_ZONE_SID, "TTSChimeDuration", dev )
		deleteVar( SONOS_ZONE_SID, "TTSChime", dev )
		deleteVar( SONOS_ZONE_SID, "UseTTSCache", dev )
		deleteVar( SONOS_ZONE_SID, "TTSCacheMaxAge", dev )
	end

	if s < _CONFIGVERSION then
		setVar( SONOS_SYS_SID, "ConfigVersion", _CONFIGVERSION, dev )
	end
end

local function systemRunOnce( pdev )
	local s = getVarNumeric( "ConfigVersion", 0, pdev, SONOS_SYS_SID )

	initVar( "Message", "", pdev, SONOS_SYS_SID )
	initVar( "Enabled", 1, pdev, SONOS_SYS_SID )
	initVar( "UseProxy", "", pdev, SONOS_SYS_SID )
	initVar( "DebugLogs", 0, pdev, SONOS_SYS_SID )
	initVar( "MaxLogSize", "", pdev, SONOS_SYS_SID )
	initVar( "CheckStateRate", "", pdev, SONOS_SYS_SID )
	initVar( "TTSChime", "", pdev, SONOS_SYS_SID )
	initVar( "UseTTSCache", "", pdev, SONOS_SYS_SID )
	initVar( "TTSCacheMaxAge", "", pdev, SONOS_SYS_SID )

	if s < 20103 and not isOpenLuup then
		for i=0,200,25 do
			local t = "Sonos_"..i..".png"
			os.remove( getInstallPath() .. t )
			os.remove( "/www/cmh/skins/default/icons/" .. t )
		end
		os.remove( "/www/cmh/skins/default/icons/Sonos.png" )
		os.remove( getInstallPath() .. "Sonos.png" )
	end

	deleteVar( SONOS_ZONE_SID, "TTSChime", pdev ) -- wrong SID
	deleteVar( SONOS_ZONE_SID, "UseTTSCache", pdev ) -- wrong SID
	deleteVar( SONOS_ZONE_SID, "TTSCacheMaxAge", pdev ) -- wrong SID

	if s < _CONFIGVERSION then
		setVar( SONOS_SYS_SID, "ConfigVersion", _CONFIGVERSION, pdev )
	end
end

local function startZone( zoneDevice )
	L("Starting zone %1 (#%2)", luup.devices[zoneDevice].description, zoneDevice)

	zoneRunOnce( zoneDevice )

	setup( zoneDevice, true )

	return true
end

local function getFreeSpace( dirname )
	local f = io.popen( "df -k '"..dirname.."'" )
	if f then
		repeat
			local l = f:read("*l")
			if l then
				local freek,pct = l:match( "%d+%s+%d+%s+(%d+)%s+(%d+)%%" )
				if freek then
					freek = tonumber( freek )
					pct = tonumber( pct )
					f:close()
					return freek,pct
				end
			end
		until not l
		f:close()
	end
	return nil
end

local function runMasterTick( task )
	D("runMasterTick(%1)", task)
	task:delay( 900 ) -- run again in 15 minutes unless scheduled otherwise

	-- Check disk space
	local panic = false
	local inst = getInstallPath()
	local f,p = getFreeSpace( inst )
	D("runMasterTick() %3 has %1K free at %2%%", f, p, inst)
	if f and f < 1024 then
		W("WARNING! Less than 1MB free space available on %2 (%1K)", f, inst)
		panic = true
	end
	if p and p >= 90 then
		W("WARNING! Free space on %2 is critical (%1%% full)", p, inst)
		panic = true
	end
	if not isOpenLuup then
		f,p = getFreeSpace( "/www/sonos/" )
		D("runMasterTick() /www/sonos has %1K free at %2%%", f, p)
		if f and f < 1024 then
			W("WARNING! Less than 1MB free space available on /www/sonos (%1K)", f)
			panic = true
		end
		if p and p >= 90 then
			W("WARNING! Free space on /www/sonos is critical (%1%% full)", p)
			panic = true
		end
	end
	if panic then
		setVar( SONOS_SYS_SID, "Message", "CHECK SYSTEM -- LOW DISK SPACE!", pluginDevice )
		luupTask( "CHECK SYSTEM -- LOW DISK SPACE", TASK_ERROR_PERM )
		if logFile then
			logFile:write("Closing log--low disk space!\n")
			logFile:close()
			logFile = nil -- set to nil so no re-open
		end
	end
end

-- Complete startup tasks. Hopefully everything is initialized by now.
local function deferredStartup(device)
	D("deferredStartup(%1)", device)
	device = tonumber(device)

	-- Allow configured no-proxy operation
	if not useProxy() then
		upnp.unuseProxy()
	else
		scheduler.Task:new("checkProxy", device, checkProxy, { device }):delay(300)
	end

	-- Find 2.x zone children
	Zones = {}
	local count, started = 0, 0
	local children = {}
	for k,v in pairs( luup.devices ) do
		if v.device_type == SONOS_ZONE_DEVICE_TYPE and v.device_num_parent == device then
			local zid = v.id or ""
			L("Found child %1 (#%2) zone %3", v.description, k, zid)
			children[k] = v
			Zones[zid] = k
			count = count + 1
			setVar(UPNP_AVTRANSPORT_SID, "CurrentStatus", "Starting...", k)
		end
	end

	-- Look for and upgrade any 1.x zones remaining that don't have 2.x devices
	local reload = false
	for k,v in pairs( luup.devices ) do
		if v.device_type == SONOS_ZONE_DEVICE_TYPE and v.device_num_parent == 0 then
			local zid = getVar( "SonosID", "", k, UPNP_DEVICE_PROPERTIES_SID )
			if zid ~= "" and not Zones[zid] then
				-- Old-style standalone; convert to child
				zid = getVar( "SonosID", tostring(k), k, UPNP_DEVICE_PROPERTIES_SID )
				W("Adopting v1.x device %2 (#%3) %4 by new parent %1", device, v.description, k, zid)
				luup.attr_set( "altid", zid, k )
				luup.attr_set( "id_parent", device, k )
				setVar( UPNP_AVTRANSPORT_SID, "CurrentStatus", "Upgrade in progress...", k )
				reload = true
			else
				-- Leave orphan zombied.
				W("Leaving old v1.x device %1 (#%2) %4 as orphan; it can be safely deleted; it has been replaced by #%3",
					v.description, k, Zones[zid], zid)
				setVar(UPNP_AVTRANSPORT_SID, "CurrentStatus", "DELETE ME!", k)
			end
			luup.attr_set( "invisible", 0, k )
			luup.attr_set( "impl_file", "", k )
			luup.attr_set( "plugin", "", k )
			-- Fix IP always (even orphan, because it can be adopted by removing new device + reload)
			local ip = luup.attr_get( "ip", k ) or ""
			if ip ~= "" then
				setVar( SONOS_ZONE_SID, "SonosIP", ip, k )
				luup.attr_set( "mac", "", k )
				luup.attr_set( "ip", "", k )
			end
			luup.set_failure( 1, k )
		end
	end
	-- And reload if devices were upgraded.
	if reload then
		setVar( SONOS_SYS_SID, "Message", "Upgrading devices... please wait", pluginDevice )
		W("Converted old standalone devices to children; reloading Luup")
		luup.reload()
		return false, "Reload required", MSG_CLASS
	end

	-- At this point, we can be considered ready. We want to allow discovery now.
	systemReady = true

	-- If there are no children, launch discovery and see if we can find some.
	-- Otherwise, check the zone topology to see if there are zones we don't have.
	if getVarNumeric( "StartupInventory", 1, device, SONOS_SYS_SID ) ~= 0 then
		if count == 0 then
			L"No children; launching discovery to see who I can find."
			luup.call_action( SONOS_SYS_SID, "StartSonosDiscovery", {}, device )
		elseif zoneInfo and next( zoneInfo.zones ) then
			-- ??? TO-DO: this may be a good opportunity to handle child devices no longer in zoneInfo
			D("deferredStartup() taking inventory")
			local newZones = {}
			for uuid in pairs( zoneInfo.zones ) do
				if not ( Zones[uuid] or newZones[uuid] ) then
					newZones[uuid] = getIPFromUUID( uuid ) or ""
				end
			end
			if next( newZones ) then
				setVar( SONOS_SYS_SID, "Message", "New device(s) found... please wait", pluginDevice )
				D("deferredStartup() rebuilding family")
				local ptr = luup.chdev.start( device )
				for k,v in pairs( children ) do
					local df = luup.attr_get('device_file', k)
					D("deferredStartup() appending existing child dev #%1 %2 uuid %3 device_file %4", k, v.description, v.id, df)
					luup.chdev.append( device, ptr, v.id, v.description, "", df, "", "", false )
				end
				for uuid,ip in pairs( newZones ) do
					D("deferredStartup() appending new zone %1 ip %2", uuid, ip)
					local cv = {
						string.format( "%s,SonosID=%s", UPNP_DEVICE_PROPERTIES_SID, uuid ),
						string.format( "%s,SonosIP=%s", SONOS_ZONE_SID, ip ),
						",invisible=0"
					}
					local name = zoneInfo.zones[uuid].ZoneName or uuid:gsub("RINCON_", "")
					luup.chdev.append( device, ptr, uuid, name, "", "D_Sonos1.xml", "",
						table.concat( cv, "\n" ), false )
				end
				luup.chdev.sync( device, ptr )
			end
		end
	end

	-- Identify and mark two lowest-numbered non-satellite zones as network masters for us.
	-- This means they will be subscribed to topology and content updates; others will not.
	L("Selecting zones for master role...")
	local chorder = {}
	local designated = {}
	for uuid,dev in pairs( Zones ) do
		setVar( SONOS_ZONE_SID, "MasterRole", 0, dev )
		if getVarNumeric( "DesignatedMaster", 0, dev, SONOS_ZONE_SID ) ~= 0 then
			L("Zone %1 %2 (#%3) is a designated master", uuid, luup.devices[dev].description, dev)
			table.insert( designated, dev )
		elseif not (zoneInfo.zones[uuid] or {}).isSatellite then
			table.insert( chorder, dev )
		else
			L("Zone %1 %2 (#%3) is satellite; cannot take master role", uuid, luup.devices[dev], dev)
		end
	end
	table.sort( chorder )
	-- Push designated master(s) to the front of the list
	for _,dev in ipairs( designated ) do table.insert( chorder, 1, dev ) end
	local nummaster = getVarNumeric( "NumMasters", 2, device, SONOS_SYS_SID )
	if nummaster > #chorder then nummaster = #chorder end
	masterZones = {}
	for k = 1, nummaster do
		local dev = chorder[k]
		L("Selected %1 (#%2) for master role", luup.devices[dev].description, dev)
		setVar( SONOS_ZONE_SID, "MasterRole", 1, dev )
		table.insert( masterZones, { device=dev, uuid=luup.devices[dev].id } )
	end
	L("Zones selected for master role: %1", masterZones)

	-- Start zones
	-- ??? Do we even need to bother to start satellites?
	for uuid,dev in pairs( Zones ) do
		local status,success = pcall( startZone, dev, uuid )
		if status and success then
			luup.set_failure( 0, dev )
			started = started + 1
		else
			W("Failed to start child %1 (#%2): %3", luup.devices[dev].description, dev, success)
			luup.set_failure( 1, dev )
			setVar(UPNP_AVTRANSPORT_SID, "CurrentStatus", tostring(success), dev)
		end
	end
	L("Started %1 children of %2", started, count)
	local proxmsg = upnp.proxyVersionAtLeast(1) and "proxy detected" or "no proxy"
	setVar( SONOS_SYS_SID, "Message", string.format("Running %d zones; %s", started, proxmsg), device )
	setVar( SONOS_SYS_SID, "DiscoveryMessage", "", device)

	-- Start a new master task
	local t = scheduler.Task:new( "master", device, runMasterTick, { device } )
	t:delay( 60 )

	-- Set visibility of zones; satellites are not visible.
	if zoneInfo then
		for uuid,zi in pairs( zoneInfo.zones or {} ) do
			local dev = Zones[uuid]
			if dev then
				D("deferredStartup() setting visibility of %1 (#%2) zone %3 satellite %4", luup.devices[dev].description,
					dev, uuid, zi.isSatellite or false)
				luup.attr_set( "invisible", zi.isSatellite and 1 or 0, dev )
			else
				W("Zone %1 has no child device--please re-run discovery.", uuid)
			end
		end
	end

	D("deferredStartup() done. We're up and running!")
end

local function waitForProxy( task, device, tries )
	D("waitForProxy(%1,%2,%3)", tostring(task), device, tries)
	tries = (tries or 0) + 1
	if getVarNumeric( "UseProxy", isOpenLuup and 0 or 1, device, SONOS_SYS_SID ) == 0
		or upnp.getProxyApiVersion() or tries >= 10 then
		-- Success or too long or no proxy, get going.
		task:close() -- close current master task; deferredStartup will create anew
		deferredStartup(device)
		return
	end
	D("waitForProxy() proxy not ready, retrying")
	setVar( SONOS_SYS_SID, "Message", "Searching for UPnP Proxy...", device )
	task:delay(3, nil, { device, tries })
end

local function checkPluginInstalled()
	local _,_,_,ra = luup.call_action( "urn:micasaverde-com:serviceId:HomeAutomationGateway1", "GetUserData", { DataFormat="json" }, 0 ) -- luacheck: ignore 311
	ra = tostring( ra.UserData )
	ra = json.decode( ra )
	for _,v in ipairs( ra.InstalledPlugins2 or {} ) do
		if v.id == PLUGIN_ID then
			return tonumber(v.Version) or false
		end
	end
	return false
end

function startup( lul_device )
	L("Starting version %1 device #%2 (%3)", PLUGIN_VERSION, lul_device,
		luup.devices[lul_device].description)

	-- Hmmm... are we a zone device that's been given the new implementation file?
	if luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE then
		E("Detected system startup on zone device. Fixing!")
		L("zone device is %1", getVar( "SonosID", "", lul_device, UPNP_DEVICE_PROPERTIES_SID ))
		luup.attr_set( "impl_file", "", lul_device )
		luup.attr_set( "device_file", "D_Sonos1.xml", lul_device )
		luup.attr_set( "plugin", "", lul_device )
		return true, "*Upgrading...", "Sonos"
	elseif luup.devices[lul_device].device_type ~= SONOS_SYS_DEVICE_TYPE then
		E("I don't know what kind of device I am! #%1, %2", lul_device, luup.devices[lul_device].device_type)
		luup.set_failure( 1, lul_device )
		return false, "Invalid device", "Sonos"
	end

	systemReady = false
	isOpenLuup = luup.openLuup ~= nil
	pluginDevice = lul_device
	unsafeLua = isOpenLuup or ( luup.attr_get( "UnsafeLua", 0 ) or "1" ) == "1"

	local debugLogs = getVarNumeric("DebugLogs", 0, lul_device, SONOS_SYS_SID)
	setDebugLogs(debugLogs)

	-- See if log file needs to be opened
	if getVarNumeric("MaxLogSize", DEVELOPMENT and 512 or 0, lul_device, SONOS_SYS_SID) > 0 then
		pcall( logToFile, string.rep( "_", 132) )
		pcall( logToFile, string.format( "Log file opened at startup; plugin %s; luup %s", PLUGIN_VERSION, luup.version) )
	end

	-- Quick pass at devices to check for duplicate master devices. Only lowest-numbered survives/runs.
	local master = lul_device
	for k,v in pairs( luup.devices ) do
		if v.device_type == SONOS_SYS_DEVICE_TYPE then
			if k < master then master = k end
		end
	end
	if lul_device ~= master then
		E("Duplicate Sonos System master device! Real master is #%1", master)
		luup.variable_set( SONOS_SYS_SID, "Message", "Duplicate master device! Delete me!", lul_device )
		luup.set_failure( 1, lul_device )
		return false, "Duplicate master device!", PLUGIN_NAME
	end

	-- Check required packages.
	for _,v in ipairs{ "socket", "socket.http", "socket.url", "ltn12", "lxp.lom", "dkjson", "lfs" } do
		local st,m = pcall( require, v )
		if not st or type(m) ~= "table" then
			L({level=1,"Required system package %1 could not be loaded. Please install it."}, v)
			luup.set_failure( 1, lul_device )
			return false, "Missing required system package", PLUGIN_NAME
		end
	end

	local installVersion = not isOpenLuup and checkPluginInstalled()
	if installVersion then
		L("Installed (App Marketplace) plugin version is %1", installVersion)
		if installVersion < 39806 then -- 28820 is 1.4, 39806 is first 2.0 RC
			E("The App Marketplace version of the v1.x plugin (%1) is installed! You must first uninstall it to run this version.", installVersion, PLUGIN_VERSION)
			luup.attr_set( "plugin", "", lul_device )
			for k,v in pairs( luup.devices ) do
				if v.device_type == SONOS_ZONE_DEVICE_TYPE then
					luup.attr_set( "plugin", "", k )
				end
			end
			setVar( SONOS_SYS_SID, "Message", "Version conflict!", lul_device )
			luup.set_failure( 1, lul_device )
			return false, "Version conflict!", PLUGIN_NAME
		elseif not DEVELOPMENT then -- >= first 2.0 RC
			-- N.B. This MUST come before systemRunOnce()
			if getVarNumeric( "ConfigVersion", 0, lul_device, SONOS_SYS_SID ) < _CONFIGVERSION then
				-- Attach to installed plugin
				L("Attaching to installed plugin")
				luup.attr_set( "plugin", PLUGIN_ID, lul_device )
			end
		end
	end
	if DEVELOPMENT then
		luup.attr_set( "plugin", "", lul_device )
	end

	systemRunOnce( lul_device )

	setVar( SONOS_SYS_SID, "PluginVersion", PLUGIN_VERSION, lul_device )
	setVar( SONOS_SYS_SID, "_UIV", _UIVERSION, lul_device )
	setVar( SONOS_SYS_SID, "Message", "Starting...", lul_device )
	setVar( SONOS_SYS_SID, "DiscoveryMessage", "Starting, please wait.", lul_device )

	local enabled = initVar( "Enabled", "1", lul_device, SONOS_SYS_SID )
	if "0" == enabled then
		W("%1 (#%2) disabled by configuration; startup aborting.", luup.devices[lul_device].description,
			lul_device)
		allOffline( lul_device )
		setVar( SONOS_SYS_SID, "Message", "Disabled", lul_device )
		return true, "Disabled", MSG_CLASS
	end

	local ipath = getInstallPath()
	for _,v in ipairs{ "D_Sonos1.json", "D_Sonos1.xml", "D_SonosSystem1.json", "D_SonosSystem1.xml",
						"I_SonosSystem1.xml", "J_Sonos1.js", "J_SonosSystem1.js", "L_SonosSystem1.lua",
						"L_SonosTTS.lua", "L_SonosUPnP.lua", "S_Sonos1.xml", "S_SonosAVTransport1.xml",
						"S_SonosGroupRenderingControl1.xml", "S_SonosRenderingControl1.xml",
						"S_SonosSystem1.xml" } do
		if file_exists( ipath .. v ) and file_exists( ipath .. v .. ".lzo" ) then
			E("Found compressed and uncompressed versions of %1; remove all plugin files and reinstall.", v)
			setVar( SONOS_SYS_SID, "Message", "Invalid install files (see log)", lul_device )
			return false, "Invalid install files (see log)", MSG_CLASS
		end
	end

	-- If VeraAlexa is installed, make sure its definition of our Sonos1 service is OUR definition.
	local unc = file_exists( ipath.."S_VeraAlexaSay1.xml" )
	local cmp = file_exists( ipath.."S_VeraAlexaSay1.xml.lzo" )
	if unc or cmp then
		L("Detected VeraAlexa plugin; syncing it to our Sonos1 service definition")
		if file_exists( ipath.."S_Sonos1.xml" ) then
			os.execute( string.format( "cp '%s/S_Sonos1.xml' '%s/S_VeraAlexaSay1.xml'", ipath, ipath ) )
		else
			os.execute( string.format( "pluto-lzo d '%s/S_Sonos1.xml.lzo' '%s/S_VeraAlexaSay1.xml'", ipath, ipath ) )
		end
		if cmp then
			os.execute( string.format( "pluto-lzo c '%s/S_VeraAlexaSay1.xml' '%s/S_VeraAlexaSay1.xml.lzo'", ipath, ipath ) )
		end
		if not unc then os.remove( ipath.."S_VeraAlexaSay1.xml" ) end
	end

	-- Disable old plugin implementation if present.
	if false and not isOpenLuup then
		-- For now, don't do this on Vera. We need our version of the impl file around to bootstrap
		-- the new version, since Luup's plugin upgrade won't create the new system device itself.
		if file_exists( ipath .. "I_Sonos1.xml.lzo" ) or file_exists( ipath .. "I_Sonos1.xml" ) then
			W("Removing old Sonos plugin implementation files (for standalone devices, no longer used)")
			os.remove(ipath.."I_Sonos1.xml.lzo")
			os.remove(ipath.."I_Sonos1.xml")
		end
	end
	-- These are removed on all platforms.
	for _,v in ipairs{ "L_Sonos1.lua", "D_Sonos1_UI4.json" } do
		if file_exists( ipath .. v .. ".lzo" ) then os.remove( ipath .. v .. ".lzo" ) end
		if file_exists( ipath .. v ) then os.remove( ipath .. v ) end
	end

	-- Find existing child zones
	Zones = {}
	for k,v in pairs( luup.devices ) do
		if v.device_type == SONOS_ZONE_DEVICE_TYPE and v.device_num_parent == lul_device then
			local zid = v.id or ""
			D("startup() found child %1 zoneid %3 parent %2", k, v.device_num_parent, zid)
			setVar(UPNP_AVTRANSPORT_SID, "CurrentStatus", "Offline; waiting for proxy...", k)
			Zones[zid] = k
			local ip = luup.attr_get( "ip", k ) or ""
			if ip ~= "" then
				setVar( SONOS_ZONE_SID, "SonosIP", ip, k )
				luup.attr_set( "mac", "", k )
				luup.attr_set( "ip", "", k )
			end
			if ( luup.attr_get( "plugin", k ) or "" ) ~= "" then
				luup.attr_set( "plugin", "", k )
			end
		elseif v.device_type == "urn:schemas-upnp-org:device:altui:1" and v.device_num_parent == 0 then
			isALTUI = k
		end
	end

	metaDataKeys = loadServicesMetaDataKeys()

	scheduler = TaskManager( 'sonosTick' )

	if not isOpenLuup then
		os.execute("mkdir -p /www/sonos/")
	end
	local x,y = pcall( fixLegacyIcons )
	if not x then E("fixLegacyIcons: %1 %2", x, y) end

	D("startup() UPnP module version is %1", upnp.VERSION)
	if ( upnp.VERSION or 0 ) < MIN_UPNP_VERSION then
		E"The L_SonosUPNP module installed is not compatible with this version of the plugin core."
		return false, "Invalid installation", MSG_CLASS
	end
	if not tts then
		L("TTS module is not installed (it's optional)")
	else
		D("startup() TTS module version is %1", tts.VERSION)
		if ( tts.VERSION or 0 ) < MIN_TTS_VERSION then
			W("The L_SonosTTS module installed may not be compatible with this version of the plugin core.")
		end
	end

	local routerIp = getVar("RouterIp", "", lul_device, SONOS_SYS_SID, true)
	local routerPort = getVar("RouterPort", "", lul_device, SONOS_SYS_SID, true)

	local fetch = getVarNumeric("FetchQueue", -1, lul_device, SONOS_SYS_SID)
	if fetch < 0 then
		setVar(SONOS_SYS_SID, "FetchQueue", "1", lul_device)
		fetch = 1
	end
	if fetch == 0 then
		fetchQueue = false
	end

	--
	-- Acquire the IP Address of Vera itself, needed for the Say method later on.
	-- Note: We're assuming Vera is connected via it's WAN Port to the Sonos devices
	--
	VERA_LOCAL_IP = getVar("LocalIP", "", lul_device, SONOS_SYS_SID, true)
	if not isOpenLuup then
		if VERA_LOCAL_IP == "" then
			local stdout = io.popen("GetNetworkState.sh ip_wan")
			VERA_LOCAL_IP = stdout:read("*a")
			stdout:close()
		else
			W("Warning: LocalIP should not be set except on openLuup!")
		end
	end
	D("startup(): controller IP address is %1", VERA_LOCAL_IP)
	if VERA_LOCAL_IP == "" then
		E("Unable to establish local IP address of Vera/openLuup system. Please set 'LocalIP'")
		luup.set_failure( 1, lul_device )
		return false, "Unable to establish local IP -- see log", PLUGIN_NAME
	elseif VERA_LOCAL_IP:match("^localhost") or VERA_LOCAL_IP == "127.0.0.1" then
		E("Invalid configuration -- `LocalIP' cannot be localhost or 127.0.0.1")
		luup.set_failure( 1, lul_device )
		return false, "Configuration error -- see log", PLUGIN_NAME
	end

	if routerIp == "" then
		VERA_IP = VERA_LOCAL_IP
	else
		VERA_IP = routerIp
	end
	if routerPort ~= "" then
		VERA_WEB_PORT = tonumber(routerPort)
	end

	upnp.initialize(L, W, E)

	if tts then
		tts.initialize(L, W, E)
		setupTTSSettings(lul_device)
	end

	port = 1400

	setVar(SONOS_SYS_SID, "DiscoveryPatchInstalled",
		upnp.isDiscoveryPatchInstalled(VERA_LOCAL_IP) and "1" or "0", lul_device)

	-- Reload zoneInfo from last known
	zoneInfo = { zones={}, groups={} }
	local s = getVar( "zoneInfo", "", lul_device, SONOS_SYS_SID )
	if s ~= "" then
		s = json.decode( s )
		if s then
			zoneInfo = s
			D("startup() reloaded zoneInfo %1", zoneInfo)
		else
			W("Saved GroupZoneTopology invalid! Ignoring.")
			luup.log(s,2)
		end
	end

	-- Deferred startup, on the master tick task.
	local t = scheduler.Task:new( "master", lul_device, waitForProxy, { lul_device } )
	t:delay( 5 )

	luup.set_failure( 0, lul_device )
	return true, "", MSG_CLASS
end

--[[

	TTS Support Functions

--]]

endSayAlert = false-- Forward declaration, non-local

local function sayOrAlert(device, parameters, saveAndRestore)
	D("sayOrAlert(%1,%2,%3)", device, parameters, saveAndRestore)
	local instanceId = defaultValue(parameters, "InstanceID", "0")
	local channel = defaultValue(parameters, "Channel", "Master")
	local volume = defaultValue(parameters, "Volume", nil)
	local forceUnmute = defaultValue(parameters, "UnMute", "1") == "1"
	local devices = defaultValue(parameters, "GroupDevices", "")
	local zones = defaultValue(parameters, "GroupZones", "")
	local uri = defaultValue(parameters, "URI", nil)
	local duration = tonumber( defaultValue( parameters, "Duration", "10" ) ) or 10
	if duration <= 0 then duration = 10 end
	local sameVolume = string.find( "|1|true|TRUE|", parameters.SameVolumeForAll or "0" )

	local targets = {}
	local newGroup = true
	local localUUID = findZoneByDevice( device )

	-- If we're using the CURRENT ZoneGroup, then we don't need to restructure groups, just
	-- announce to the coordinator of the group (so set that up if needed). In all other cases,
	-- we restructure to a temporary group, for which the current `device` is the coordinator.
	if zones:upper() == "CURRENT" then
		_, localUUID = controlByCoordinator( localUUID )
		targets = { [localUUID]=true }
		newGroup = false
	elseif zones:upper() == "ALL" then
		local _, lt = getAllUUIDs()
		targets = map( lt ) -- array of UUIDs to table with UUIDs as keys
	else
		local uuid
		for id in devices:gmatch("[^,]+") do
			local nid = tonumber(id)
			if not nid then
				W("Say/Alert action GroupDevices device %1 not a valid device number (ignored)", id)
			elseif not findZoneByDevice( nid ) then
				W("Say/Alert action GroupDevices device %1 not a known Sonos device (ignored)", id)
			else
				uuid = findZoneByDevice( nid )
			end
			if (uuid or "") ~= "" then
				targets[uuid] = true
			end
		end
		for zone in zones:gmatch("[^,]+") do
			if zone:match( 'RINCON_%x+' ) then
				uuid = zone
			else
				uuid = getUUIDFromZoneName( zone )
			end
			if (uuid or "") ~= "" then
				targets[uuid] = true
			end
		end
	end
	D("sayOrAlert() targets are %1", targets)

	if saveAndRestore and not sayPlayback[device] then
		-- Save context for all affected members. For starters, this is all target members.
		targets[localUUID] = true -- we always save context for the controlling device
		local affected = clone( targets )
		D("sayOrAlert() affected is %1", affected)

		-- Now, find any targets that happen to be coordinators of groups. All members are also
		-- affected by removing/changing the coordinator when the temporary alert group is created.
		for uuid in pairs( targets ) do
			local gr = getZoneGroup( uuid ) or {}
			D("sayOrAlert() zone group for target %1 is %2", uuid, gr)
			if gr.Coordinator == uuid and #gr.members > 1 then
				-- Target is a group coordinator; add all group members to affected list
				D("sayOrAlert() %1 is coordinator, adding group members to affected list", uuid)
				affected = map( gr.members, nil, affected )
			end
		end

		-- Save state for all affected members
		sayPlayback[device] = savePlaybackContexts( device, keys( affected ) )
		sayPlayback[device].newGroup = newGroup -- signal to endSay
		sayPlayback[device].coordinator = localUUID --save temporary coordinator for clean ungroup
		D("sayOrAlert() final affected list is %1 newGroup %2 coord %3", affected, newGroup, localUUID)

		-- Pause all affected zones. If we need a temporary group, remove all non-coordinators;
		-- this leaves all affected players as standalone. playURI will do the grouping.
		for uuid in pairs( affected ) do
			local gr = getZoneGroup( uuid ) or {}
			local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
			if AVTransport then
				AVTransport.Pause({InstanceID=instanceId})
				if newGroup and uuid ~= gr.Coordinator then
					D("sayOrAlert() removing group association for affected zone %1", uuid)
					AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID=instanceId})
				end
			end

			-- Maybe unmute
			if forceUnmute and dataTable[uuid].Mute == "1" then
				local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
				if Rendering then
					Rendering.SetMute(
						{OrderedArgs={"InstanceID=" .. instanceId,
										"Channel=" .. channel,
										"DesiredMute=0"}})
				end
			end
		end
	end

	-- zoneUUID, instanceId, uri, speed, volume, uuids, sameVolumeForAll, enqueueMode, newGroup, controlByGroup
	playURI(localUUID, instanceId, uri, "1", volume, newGroup and keys(targets) or nil, sameVolume, nil, newGroup, true)

	if saveAndRestore then
		D("sayOrAlert() delaying for duration %1", duration)
		local t = scheduler.getTask("endSayAlert"..device) or scheduler.Task:new("endSayAlert"..device, device, endSayAlert, { device })
		t:delay( duration, { replace=true } )
	end

	updateNow( device )
end

local function queueAlert(device, settings)
	D("queueAlert(%1,%2)", device, settings)
	sayQueue[device] = sayQueue[device] or {}

	-- If empty URI is passed, abandon all queued TTS/alerts.
	if (settings.URI or "") == "" then
		if sayPlayback[device] then
			-- Leave queue with currently playing element (if any)
			while sayQueue[device] and #sayQueue[device] > 1 do
				table.remove( sayQueue[device] )
			end
			-- Rush the end task, if any
			local task = scheduler.getTask( "endSayAlert"..device)
			if task then
				task:delay( 0, { replace=true } )
			end
		end
		return
	end

	local first = #sayQueue[device] == 0
	local rept = tonumber( settings.Repeat ) or 1
	if rept < 1 then rept = 1 end
	while rept > 0 do
		table.insert(sayQueue[device], settings)
		rept = rept - 1
	end

	-- First one kicks things off
	if first then
		sayOrAlert(device, settings, true)
	end
end

-- This TTS audio is done. More?
local function endTTSPlayback(device)
	D("endTTSPlayback(%1)", device)
	if sayQueue[device] and #sayQueue[device] > 0 then
		local settings = sayQueue[device][1]
		D("endTTSPlayback() finished %1", settings.URI)
		-- Don't delete temp file; we may need for repeats, useful for debug/diag.
		table.remove(sayQueue[device], 1)
		D("endTTSPlayback() queue contains %1 more", #sayQueue[device])
		if #sayQueue[device] > 0 then
			sayOrAlert(device, sayQueue[device][1], true)
			return false
		end
	end
	D("endTTSPlayback() queue now empty")
	sayQueue[device] = nil
	return true -- finished
end

-- Callback (task) for end of Alert/Say action.
endSayAlert = function(task, device)
	D("endSayAlert(%1,%2)", tostring(task), device)
	if endTTSPlayback(device) then
		task:close() -- no longer needed
		if sayPlayback[device] then
			-- Playback state was saved, so restore it.
			local playCxt = sayPlayback[device]
			if playCxt.newGroup then
				--[[ Temporary group was used; reset group structure. First remove all to-be-restored
					 devices from their current groups. It seems quite important to the zones that
					 they are removed from the coordinator, but the coordinator itself isn't touched.
				--]]
				D("endSayAlert() restoring group structure after temporary group")
				for uuid in pairs( playCxt.context or {} ) do
					if uuid ~= playCxt.coordinator then
						D("endSayAlert() clearing group for %1", uuid)
						local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
						if AVTransport ~= nil then
							AVTransport.Stop({InstanceID="0"})
							AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID="0"})
						end
					else
						D("endSayAlert() %1 is coordinator of temporary group", uuid)
					end
				end

				D("endSayAlert() restoring group structure")
				for uuid,cxt in pairs( playCxt.context or {} ) do
					-- D("endSayAlert() affected %1 context ", uuid, cxt)
					if cxt.GroupCoordinator ~= uuid then
						D("endSayAlert() restoring member %1 to %2", uuid, cxt.GroupCoordinator)
						-- Add this uuid to its prior GroupCoordinator
						if controlAnotherZone( uuid, findZoneByDevice( device ) ) then
							playURI(uuid, "0", "x-rincon:" .. cxt.GroupCoordinator, "1", nil, nil, false, nil, false, false)
						end
					else
						D("endSayAlert() %1 is its own group coordinator", uuid)
					end
				end
			end

			D("endSayAlert() restoring saved playback contexts")
			restorePlaybackContexts(device, playCxt)
			sayPlayback[device] = nil
		end
	end
end

-- Quick and dirty hash for cache
local function hash(t)
	local s = #t
	for k=1,#t do
		s = ( s + t:byte(k) ) % 64
	end
	return s
end

local function loadTTSCache( engine, language, hashcode )
	D("loadTTSCache(%1,%2,%3)", engine, language, hashcode)
	local curl = string.format( "ttscache/%s/%s/%d/", tostring(engine), tostring(language), tostring(hashcode) )
	local cpath = TTSBasePath .. curl
	local fm = io.open( cpath .. "ttsmeta.json", "r" )
	if fm then
		local fmeta = json.decode( fm:read("*a") )
		fm:close()
		if fmeta and fmeta.version == 1 and fmeta.strings then
			return fmeta, curl
		end
		W("(tts) clearing cache path %1", cpath)
		os.execute("rm -rf -- " .. Q(cpath))
	end
	return { version=1, nextfile=1, strings={} }, curl
end

local function saveTTSCache( engine, language, hashcode, fmeta )
	D("saveTTSCache(%1,%2,%3,%4)", engine, language, hashcode, fmeta )
	local cpath = string.format( "%sttscache/%s/%s/%d/ttsmeta.json",
		TTSBasePath, tostring(engine), tostring(language), tostring(hashcode) )
	local fm = io.open( cpath, "w" )
	if fm then
		fm:write( json.encode( fmeta ) )
		fm:close()
		return true
	end
	return false
end

-- Cache cleaning task.
local function cleanTTSCache( task )
	local maxAge = 86400 * getVarNumeric( "TTSCacheMaxAge", 90, pluginDevice, SONOS_SYS_SID )
	if maxAge <= 0 then return end
	maxAge = os.time() - maxAge
	L("Cleaning TTS cache of files older than %1", os.date("%x %X", maxAge))
	function scan( d )
		D("cleanTTSCache() scanning %1", d)
		-- See if directory contains a cache meta
		local fm = io.open( d .. "/ttsmeta.json", "r" )
		if fm then
			D("cleanTTSCache() reading TTSMeta in %1", d)
			local fmeta = json.decode( fm:read("*a") )
			fm:close()
			if fmeta then
				local dels = {}
				local modified = false
				for str,md in pairs( fmeta.strings or {} ) do
					if not md.lastused then
						D("cleanTTSCache() no timestamp for %1 file %2", str, md.url)
						md.lastused = os.time() -- stamp it now, catch it later
						modified = true
					elseif md.lastused <= maxAge and not md.protected then
						D("cleanTTSCache() expired %1 file %2", str, md.url)
						table.insert( dels, str )
					end
				end
				for _,str in ipairs( dels ) do
					local p = TTSBasePath .. fmeta.strings[ str ].url
					if os.remove( p ) then
						fmeta.strings[ str ] = nil
						modified = true
						L("Removed expired cached speech audio file %1 for %2", p, str)
					else
						W("Can't remove expired cached speech audio file %1", p)
					end
				end
				-- If no strings remain, remove cache metafile. Otherwise, save if modified.
				if not next( fmeta.strings ) then
					os.remove( d .. "/ttsmeta.json" )
				elseif modified then
					fm = io.open( d .. "/ttsmeta.json", "w" )
					fm:write( json.encode( fmeta ) )
					fm:close()
				end
			else
				E("Broken TTS cache metadata in %1", d)
			end
		end
		for dd in lfs.dir( d ) do
			local path = d .. "/" .. dd
			mode = lfs.attributes( path, { "mode" } )["mode"]
			if mode == "directory" and not dd:match( "^%.%.?$") then
				scan( d .. "/" .. dd )
			end
		end
	end
	scan( TTSBasePath .. "ttscache" )

	-- Reschedule next run for tomorrow (hey, we're optimists).
	task:delay( 86400 )
end

local function makeTTSAlert( device, settings )
	local s = getVar( "TTSConfig", "", pluginDevice, SONOS_SYS_SID )
	TTSConfig = json.decode( s ) or { defaultengine=tts.getDefaultEngineId(), engines={} }
	local eid = (settings.Engine or "") ~= "" and settings.Engine or TTSConfig.defaultengine or
		tts.getDefaultEngineId()

	local engobj = tts.getEngine( eid )
	if not engobj then
		W("No TTS engine implementation for %1", eid)
		return nil
	end

	local text = settings.Text or "1 2 3"
	local opt = TTSConfig.engines[eid] or {}
	if (settings.Language or "") ~= "" then
		opt.lang = settings.Language
	end

	local voice
	if engobj.optionMeta.voice then
		voice = opt.voice or engobj.optionMeta.voice.default or tts.DEFAULT_LANGUAGE
	elseif engobj.optionMeta.lang then
		voice = opt.lang or engobj.optionMeta.lang.default or tts.DEFAULT_LANGUAGE
	else
		voice = tts.DEFAULT_LANGUAGE
	end
	cacheTTS = not file_exists( TTSBasePath .. "no-tts-cache" ) and
		getVarNumeric( "UseTTSCache", 1, pluginDevice, SONOS_SYS_SID ) ~= 0
	if cacheTTS and settings.UseCache ~= "0" then
		local fmeta = loadTTSCache( eid, voice, hash(text) )
		D("makeTTSAlert() checking cache for %1: %2", text, fmeta)
		if fmeta.strings[text] then
			D("makeTTSAlert() found it!")
			fmeta.strings[text].lastused = os.time()
			saveTTSCache( eid, voice, hash(text), fmeta )
			settings.Duration = fmeta.strings[text].duration
			settings.URI = TTSBaseURL .. fmeta.strings[text].url
			settings.URIMetadata = TTS_METADATA:format(engobj.title, engobj.protocol,
				settings.URI or "")
			settings.TempFile = nil -- flag no delete in endPlayback
			local t = scheduler.getTask( "TTSCacheCleaner" )
			if not t then
				t = scheduler.Task:new( "TTSCacheCleaner", pluginDevice, cleanTTSCache )
				t:delay( 60 )
			end
			L("(TTS) Speaking phrase from cache: %1", settings.URI)
			return settings
		end
	else
		D("(tts) caching disabled")
	end
	D("makeTTSAlert() not cached, creating")

	-- Convert text to speech using specified engine
	local file = string.format( "Say.%s.%s", tostring(device), engobj.fileType or "mp3" )
	local destFile = TTSBasePath .. file
	settings.Duration = tts.generate(engobj, text, destFile, opt)
	if (settings.Duration or 0) == 0 then
		W("(tts) Engine %1 produced no audio", engobj.title)
		return
	end
	settings.URI = TTSBaseURL .. file
	settings.TempFile = destFile
	settings.URIMetadata = TTS_METADATA:format(engobj.title, engobj.protocol,
		settings.URI)
	L("(TTS) Engine %1 created %2", engobj.title, settings.URI)
	if cacheTTS and settings.UseCache ~= "0" then
		-- Save in cache
		local fmeta, curl = loadTTSCache( eid, voice, hash(text) )
		local cpath = TTSBasePath .. curl
		local ft = file:match("[^/]+$"):match("%.[^%.]+$") or ""
		os.execute("mkdir -p " .. Q(cpath))
		while true do
			local zf = io.open( cpath .. fmeta.nextfile .. ft, "r" )
			if not zf then break end
			zf:close()
			fmeta.nextfile = fmeta.nextfile + 1
		end
		local cachefile = cpath .. fmeta.nextfile .. ft
		if os.execute( "cp -f -- " .. Q( destFile ) .. " " .. Q( cachefile ) ) ~= 0 then
			W("(TTS) Cache failed to copy %1 to %2", destFile, cachefile)
		else
			fmeta.strings[text] = { duration=settings.Duration, url=curl .. fmeta.nextfile .. ft,
				created=os.time(), lastused=os.time() }
			fmeta.nextfile = fmeta.nextfile + 1
			if not saveTTSCache( eid, voice, hash(text), fmeta ) then
				W("(TTS) Can't write cache meta in %1", cpath)
				os.remove( cachefile )
			else
				D("makeTTSAlert() cached %1 as %2", destFile, fmeta.strings[text].url)
				local t = scheduler.getTask( "TTSCacheCleaner" )
				if not t then
					t = scheduler.Task:new( "TTSCacheCleaner", pluginDevice, cleanTTSCache )
					t:delay( 60 )
				end
			end
		end
	else
		D("(tts) caching disabled, not saving generated audio")
	end
	return settings
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:micasaverde-com:serviceId:Sonos1

--]]

function actionSonosSay( lul_device, lul_settings )
	D("actionSonosSay(%1,%2)", lul_device, lul_settings)
	L("Say action on device %1 text %2", lul_device, lul_settings.Text)
	if not tts then
		W"The Sonos TTS module is not installed or could not be loaded."
		return 2,0
	end
	if ( tts.VERSION or 0 ) < MIN_TTS_VERSION then
		W"The L_SonosTTS module installed may not be compatible with this version of the plugin core."
	end
	if not unsafeLua then
		W"Some engines used with the TTS module require that 'Enable Unsafe Lua' (under 'Users & Account Info > Security') be enabled in your controller settings. If your TTS actions fail, try enabling this setting."
	end
	-- ??? Request handler doesn't unescape?
	lul_settings.Text = url.unescape( lul_settings.Text )
	-- Play as alert.
	local alert_settings = makeTTSAlert( lul_device, lul_settings )
	if alert_settings then
		if TTSChime and lul_settings.Chime ~= "0" and #(sayQueue[lul_device] or {}) == 0 then
			local ch = clone( TTSChime )
			ch.GroupDevices = alert_settings.GroupDevices
			ch.GroupZones = alert_settings.GroupZones
			ch.Volume = (ch.Volume or 0) > 0 and ch.Volume or alert_settings.Volume
			ch.SameVolumeForAll = alert_settings.SameVolumeForAll
			ch.UnMute = alert_settings.UnMute
			ch.Repeat = 1
			queueAlert( lul_device, ch )

			-- Override alert settings to use same zone group as chime
			alert_settings.GroupDevices = nil
			alert_settings.GroupZones = "CURRENT"
		end
		queueAlert( lul_device, alert_settings )
	end
	return 4,0
end

function actionSonosSetupTTS( lul_device, lul_settings )
	D("actionSonosSetupTTS(%1,%2)", lul_device, lul_settings )
	return true
end

function actionSonosResetTTS( lul_device )
	assert(luup.devices[lul_device].device_type == SONOS_SYS_DEVICE_TYPE)
	os.execute( "rm -rf -- " .. Q(TTSBasePath, "ttscache") )
	return true
end

function actionSonosSetURIToPlay( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local uri = defaultValue(lul_settings, "URIToPlay", "")

	playURI(findZoneByDevice( lul_device ), instanceId, uri, nil, nil, nil, false, nil, false, true)

	updateNow( lul_device )

	-- URI must include protocol as prefix.
	-- x-file-cifs:
	-- file:
	-- x-rincon:
	-- x-rincon-mp3radio:
	-- x-rincon-playlist:
	-- x-rincon-queue:
	-- x-rincon-stream:
	-- example is DR Jazz Radio: x-rincon-mp3radio://live-icy.gss.dr.dk:8000/Channel22_HQ.mp3
	return 4,0
end

function actionSonosPlayURI( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local uri = defaultValue(lul_settings, "URIToPlay", "")
	local volume = defaultValue(lul_settings, "Volume", nil)
	local speed = defaultValue(lul_settings, "Speed", "1")

	playURI(findZoneByDevice( lul_device ), instanceId, uri, speed, volume, nil, false, nil, false, true)

	updateNow( lul_device )

	-- URI must include protocol as prefix.
	-- x-file-cifs:
	-- file:
	-- x-rincon:
	-- x-rincon-mp3radio:
	-- x-rincon-playlist:
	-- x-rincon-queue:
	-- x-rincon-stream:
	-- example is DR Jazz Radio: x-rincon-mp3radio://live-icy.gss.dr.dk:8000/Channel22_HQ.mp3
	return 4,0
end

function actionSonosEnqueueURI( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local uri = defaultValue(lul_settings, "URIToEnqueue", "")
	local enqueueMode = defaultValue(lul_settings, "EnqueueMode", "ENQUEUE_AND_PLAY")

	playURI(findZoneByDevice( lul_device ), instanceId, uri, "1", nil, nil, false, enqueueMode, false, true)

	updateNow( lul_device )
	return 4,0
end

function actionSonosAlert( lul_device, lul_settings )
	D("actionSonosAlert(%1,%2)", lul_device, lul_settings)
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	L("Alert action on device %1 URI %2 duration %3", lul_device, lul_settings.URI, lul_settings.Duration)
	queueAlert(lul_device, lul_settings)
	return 4,0
end

function actionSonosPauseAll( lul_device, lul_settings ) -- luacheck: ignore 212
	pauseAll(lul_device)
	return 4,0
end

function actionSonosJoinGroup( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local zone = defaultValue(lul_settings, "Zone", "")
	joinGroup(findZoneByDevice( lul_device ), zone)
	return 4,0
end

function actionSonoLeaveGroup( lul_device, lul_settings ) -- luacheck: ignore 212
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	leaveGroup(findZoneByDevice( lul_device ))
	return 4,0
end

function actionSonosUpdateGroupMembers( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local zones = url.unescape(defaultValue(lul_settings, "Zones", ""))
	updateGroupMembers(findZoneByDevice( lul_device ), zones)
	return 4,0
end

function actionSonosSavePlaybackContext( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_SYS_DEVICE_TYPE)
	local devices = defaultValue(lul_settings, "GroupDevices", "")
	local zones = defaultValue(lul_settings, "GroupZones", "")

	local targets = { findZoneByDevice( lul_device ) }

	if (zones:upper() == "ALL") then
		_, targets = getAllUUIDs()
	else
		for id in devices:gmatch("[^,]+") do
			local nid = tonumber(id)
			local uuid = nil
			if not ( nid and findZoneByDevice( nid ) ) then
				W("SavePlaybackContext action GroupDevices element %1 invalid or unknown device", id)
			else
				uuid = findZoneByDevice( nid )
			end
			if uuid then
				targets[uuid] = true
			end
		end
		for zone in zones:gmatch("[^,]+") do
			if zone:match("RINCON_%x+") then
				targets[zone] = true
			else
				local uuid = getUUIDFromZoneName(zone)
				if (uuid or "") ~= "" then
					targets[uuid] = true
				end
			end
		end
	end

	playbackCxt[lul_device] = savePlaybackContexts(lul_device, targets)
	return 4,0
end

function actionSonosRestorePlaybackContext( lul_device, lul_settings ) -- luacheck: ignore 212
	assert(luup.devices[lul_device].device_type == SONOS_SYS_DEVICE_TYPE)
	restorePlaybackContexts(lul_device, playbackCxt[lul_device])
	return 4,0
end

function actionSonosStartDiscovery( lul_device, lul_settings ) -- luacheck: ignore 212
	assert(luup.devices[lul_device].device_type == SONOS_SYS_DEVICE_TYPE)
	assert(systemReady, "System is not yet ready")
	setVariableValue(SONOS_SYS_SID, "DiscoveryMessage", "Scanning...", lul_device)
	local xml, devices = upnp.scanUPnPDevices("urn:schemas-upnp-org:device:ZonePlayer:1", { "modelName", "roomName", "displayName" })
	setVariableValue(SONOS_SYS_SID, "DiscoveryResult", xml, lul_device)
	if not devices then
		setVariableValue(SONOS_SYS_SID, "DiscoveryMessage", "Aborted. See log for errors.", lul_device)
	else
		D("actionSonosStartDiscovery() discovered %1", devices)
		local children = {}
		for n,v in pairs(luup.devices) do
			if v.device_num_parent == lul_device then
				children[v.id] = n
			end
		end
		local newChildren = {}
		for _,zone in ipairs(devices) do
			if zone.udn then
				local zoneDev = children[zone.udn]
				if not zoneDev then
					-- New zone
					D("actionSonosStartDiscovery() new zone %1", zone)
					table.insert( newChildren, zone )
				elseif zone.ip ~= getVar( "SonosIP", "", zoneDev, SONOS_ZONE_SID ) then
					-- Existing zone, IP changed
					L("Discovery detected IP address change for %1 (#%3 %4) to %2",
						zone.udn, zone.ip, zoneDev, luup.devices[zoneDev].description)
					luup.attr_set( "mac", "", zoneDev )
					luup.attr_set( "ip", "", zoneDev )
					setVar( SONOS_ZONE_SID, "SonosIP", zone.ip, zoneDev )
					-- Force zoneInfo to agree with discovery
					if zoneInfo and zoneInfo.zones[zone.udn] then
						D("actionSonosStartDiscovery() forcing zoneInfo location for %1 to %2",
							zone.udn, zone.descriptionURL)
						zoneInfo.zones[zone.udn].Location = zone.descriptionURL
					end
					setup( zoneDev, true )
				end
			end
		end
		D("actionSonosStartDiscovery() new zones %1", newChildren)
		if #newChildren > 0 then
			setVariableValue(SONOS_SYS_SID, "DiscoveryMessage",
				string.format("Found %s new zones; creating devices...", #newChildren), lul_device)
			local ptr = luup.chdev.start( lul_device )
			for uuid,k in pairs( children ) do
				local df = luup.attr_get('device_file', k)
				D("actionSonosStartDiscovery() appending existing child dev #%1 %2 uuid %3 device_file %4",
					k, luup.devices[k].description, uuid, df)
				luup.chdev.append( lul_device, ptr, uuid, luup.devices[k].description, "", df, "", "", false )
			end
			for _,zone in ipairs( newChildren ) do
				D("actionSonosStartDiscovery() appending new zone %1 ip %2:%3", zone.udn, zone.ip, zone.port or 1400)
				local cv = {}
				table.insert( cv, ",manufacturer=Sonos" )
				table.insert( cv, string.format( ",model=%s", zone.modelName or "" ) )
				table.insert( cv, ",invisible=0" )
				table.insert( cv, string.format( "%s,SonosID=%s", UPNP_DEVICE_PROPERTIES_SID, zone.udn ) )
				table.insert( cv, string.format( "%s,SonosIP=%s", SONOS_ZONE_SID, zone.ip ) )
				table.insert( cv, string.format( "%s,Port=%s", SONOS_ZONE_SID, zone.port or 1400 ) )
				local w = {}
				if (zone.roomName or "") ~= "" then table.insert( w, zone.roomName ) end
				if (zone.displayName or "") ~= "" then table.insert( w, zone.displayName ) end
				if #w == 0 then
					if (zone.modelName or "") ~= "" then
						table.insert( w, zone.modelName )
					else
						table.insert( w, ( zone.udn:upper():gsub("^RINCON_","") ) ) -- N.B. gsub returns 2 values
					end
				end
				local name = table.concat( w, " " )
				luup.chdev.append( lul_device, ptr, zone.udn, name, "", "D_Sonos1.xml", "",
					table.concat( cv, "\n" ), false )
			end
			setVariableValue(SONOS_SYS_SID, "DiscoveryMessage",
				string.format("Completed. %s new zones added.", #newChildren), lul_device)
			L("Discovery complete. %1 new zones added. Requesting Luup reload.", #newChildren)
			luup.chdev.sync( lul_device, ptr )
		else
			setVariableValue(SONOS_SYS_SID, "DiscoveryMessage", "Completed. No new devices found.", lul_device)
			L"Discovery complete. No new zones found."
		end
	end
	return 4,0
end

function actionSonosSystemIncludeIP( lul_device, lul_settings )
	D("actionSonosSystemIncludeIP(%1,%2)", lul_device, lul_settings)
	assert(systemReady, "System is not yet ready")
	local ipaddr,rest = string.match( lul_settings.IPAddress or "", "^(%d+%.%d+%.%d+%.%d+)(.*)" )
	if not ipaddr then
		E("IncludeIP action: invalid IP address %1", lul_settings.IPAddress)
		setVar(SONOS_SYS_SID, "DiscoveryMessage", "Aborted; invalid address", lul_device)
		return 2,0
	end
	local port = 1400
	if rest then
		port = tonumber( rest:sub(2) ) or 1400
	end

	-- Fetch DD
	setVariableValue(SONOS_SYS_SID, "DiscoveryMessage", string.format("Querying %s", ipaddr), lul_device)
	D("Fetching zone description from %1:%2", ipaddr, port)
	local descr = upnp.UPnP_getDeviceDescription( string.format("http://%s:%s/xml/device_description.xml", ipaddr, port) )
	if not descr then
		E("Failed to read zone data from %1 -- is a Sonos Zone Player? Is it up and rinning?", ipaddr)
		setVar(SONOS_SYS_SID, "DiscoveryMessage", "Aborted; no/invalid response from "..ipaddr, lul_device)
		return 2,0
	end

	local zone = upnp.getInfosFromDescription( descr, "urn:schemas-upnp-org:device:ZonePlayer:1", { "UDN", "modelName", "roomName", "displayName" } )
	D("actionSonosSystemIncludeIP() zone info %1", zone)
	local uuid = string.gsub( zone.UDN or "", "^uuid:", "" )

	local children = {}
	for k,v in pairs(luup.devices) do
		if v.device_num_parent == lul_device then
			children[v.id] = k
			if v.device_type == SONOS_ZONE_DEVICE_TYPE then
				local ipr = getVar( "SonosIP", "", k, SONOS_ZONE_SID )
				if v.id == uuid or ipr == ipaddr then
					E("Zone at IP %1 already known as child %2 (#%3) %4", ipaddr,
						v.description, k, v.id)
					setVar(SONOS_SYS_SID, "DiscoveryMessage", "Aborted; zone already known", lul_device)
					return 2,0
				end
			end
		end
	end

	L("Including new zone %1 ip %2:%3", uuid, ipaddr, zone.port or 1400)
	setVariableValue(SONOS_SYS_SID, "DiscoveryMessage", string.format("Including %s", ipaddr), lul_device)

	local ptr = luup.chdev.start( lul_device )
	for uc,k in pairs( children ) do
		local df = luup.attr_get('device_file', k)
		D("actionSonosSystemIncludeIP() appending existing child dev #%1 %2 uuid %3 device_file %4",
			k, luup.devices[k].description, uc, df)
		luup.chdev.append( lul_device, ptr, uc, luup.devices[k].description, "", df, "", "", false )
	end
	local cv = {}
	table.insert( cv, ",manufacturer=Sonos" )
	table.insert( cv, string.format( ",model=%s", zone.modelName or "" ) )
	table.insert( cv, ",invisible=0" )
	table.insert( cv, string.format( "%s,SonosID=%s", UPNP_DEVICE_PROPERTIES_SID, uuid ) )
	table.insert( cv, string.format( "%s,SonosIP=%s", SONOS_ZONE_SID, ipaddr ) )
	table.insert( cv, string.format( "%s,Port=%s", SONOS_ZONE_SID, zone.port or 1400 ) )
	local w = {}
	if (zone.roomName or "") ~= "" then table.insert( w, zone.roomName ) end
	if (zone.displayName or "") ~= "" then table.insert( w, zone.displayName ) end
	if #w == 0 then
		if (zone.modelName or "") ~= "" then
			table.insert( w, zone.modelName )
		else
			table.insert( w, ( uuid:upper():gsub("^RINCON_","" ) ) ) -- N.B. gsub returns 2 values
		end
	end
	local name = table.concat( w, " " )
	luup.chdev.append( lul_device, ptr, uuid, name, "", "D_Sonos1.xml", "",
		table.concat( cv, "\n" ), false )

	L("Include complete. New device: %1", name)
	luup.chdev.sync( lul_device, ptr )
	return 4,0
end

function actionSonosSelectDevice( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local newDescrURL = url.unescape( lul_settings.URL or "" )
	local newIP, newPort = newDescrURL:match("http://([%d%.]-):(%d+)/.-")
	if (newIP ~= nil and newPort ~= nil) then
		luup.attr_set("ip", "", lul_device)
		luup.attr_set("mac", "", lul_device)
		setVar( SONOS_ZONE_SID, "SonosIP", newIP, lul_device )
		setup(lul_device, false)
	end
	return 4,0
end

function actionSonosSearchAndSelect( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	if (lul_settings.Name == nil or lul_settings.Name == "") then
		return 2,0
	end

	local descrURL = upnp.searchUPnPDevices("urn:schemas-upnp-org:device:ZonePlayer:1",
											lul_settings.Name,
											lul_settings.IP)
	if (descrURL ~= nil) then
		local newIP, newPort = descrURL:match("http://([%d%.]-):(%d+)/.-")
	    if (newIP ~= nil and newPort ~= nil) then
			luup.attr_set("ip", "", lul_device)
			luup.attr_set("mac", "", lul_device)
			setVar( SONOS_ZONE_SID, "SonosIP", newIP, lul_device )
			setup(lul_device, false)
		end
	end
	return 4,0
end

function actionSonosSetCheckStateRate( lul_device, lul_settings )
	setCheckStateRate(lul_device, lul_settings.rate)
	return 4,0
end

function actionSonosSetDebugLogs( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_SYS_DEVICE_TYPE)
	local val = tonumber(lul_settings.enable)
	if not val then
		val = string.find(":true:t:yes:y:1:", tostring(lul_settings.enable):lower()) and 1 or 0
	end
	luup.variable_set(SONOS_SYS_SID, "DebugLogs", val, lul_device)
	setDebugLogs(val)
	return true
end

function actionSonosSetReadQueueContent( lul_device, lul_settings )
	setReadQueueContent(lul_device, lul_settings.enable)
	return 4,0
end

function actionSonosInstallDiscoveryPatch( lul_device, lul_settings ) -- luacheck: ignore 212
	assert(luup.devices[lul_device].device_type == SONOS_SYS_DEVICE_TYPE)
	local reload = false
	if not isOpenLuup and upnp.installDiscoveryPatch(VERA_LOCAL_IP) then
		reload = true
		L("Discovery patch now installed")
	else
		L("Discovery patch installation failed")
	end
	luup.variable_set(SONOS_SYS_SID, "DiscoveryPatchInstalled",
		upnp.isDiscoveryPatchInstalled(VERA_LOCAL_IP) and "1" or "0", lul_device)
	if reload then
		scheduler.delay( SonosReload, 2 )
	end
	return 4,0
end

function actionSonosUninstallDiscoveryPatch( lul_device, lul_settings ) -- luacheck: ignore 212
	assert(luup.devices[lul_device].device_type == SONOS_SYS_DEVICE_TYPE)
	local reload = false
	if not isOpenLuup and upnp.uninstallDiscoveryPatch(VERA_LOCAL_IP) then
		reload = true
		L("Discovery patch now uninstalled")
	else
		L("Discovery patch uninstallation failed")
	end
	luup.variable_set(SONOS_SYS_SID, "DiscoveryPatchInstalled",
		upnp.isDiscoveryPatchInstalled(VERA_LOCAL_IP) and "1" or "0", lul_device)
	if reload then
		scheduler.delay( SonosReload, 2 )
	end
	return 4,0
end

function actionSonosNotifyRenderingChange( lul_device, lul_settings )
	local uuid = findZoneByDevice( lul_device )
	-- D("actionSonosNotifyRenderingChange(%1,%2)", lul_device, lul_settings)
	D("actionSonosNotifyRenderingChange(%1, lul_settings) zone %2", lul_device, uuid)
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	assert( uuid ~= nil )
	assert( EventSubscriptions[uuid] ~= nil )
	if (upnp.isValidNotification("NotifyRenderingChange", lul_settings.sid, EventSubscriptions[uuid])) then
		handleRenderingChange(uuid, lul_settings.LastChange or "")
		return 4,0
	end
	return 2,0
end

function actionSonosNotifyAVTransportChange( lul_device, lul_settings )
	local uuid = findZoneByDevice( lul_device )
	-- D("actionSonosNotifyAVTransportChange(%1,%2)", lul_device, lul_settings)
	D("actionSonosNotifyAVTransportChange(%1, lul_settings) zone %2", lul_device, uuid)
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	assert( uuid ~= nil )
	assert( EventSubscriptions[uuid] ~= nil )
	if (upnp.isValidNotification("NotifyAVTransportChange", lul_settings.sid, EventSubscriptions[uuid])) then
		handleAVTransportChange(uuid, lul_settings.LastChange or "")
		return 4,0
	end
	return 2,0
end

function actionSonosNotifyMusicServicesChange( lul_device, lul_settings ) -- luacheck: ignore 212
	local uuid = findZoneByDevice( lul_device )
	-- D("actionSonosNotifyMusicServicesChange(%1,%2)", lul_device, lul_settings)
	D("actionSonosNotifyMusicServicesChange(%1, lul_settings) uuid %2", lul_device, uuid)
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	assert( uuid ~= nil )
	assert( EventSubscriptions[uuid] ~= nil )
	if (upnp.isValidNotification("NotifyMusicServicesChange", lul_settings.sid, EventSubscriptions[uuid])) then
		-- log("NotifyMusicServicesChange for device " .. lul_device .. " SID " .. lul_settings.sid .. " with value " .. (lul_settings.LastChange or "nil"))
		sonosServices = getAvailableServices(uuid)
		metaDataKeys = loadServicesMetaDataKeys()
		return 4,0
	end
	return 2,0
end

function actionSonosNotifyZoneGroupTopologyChange( lul_device, lul_settings )
	local uuid = findZoneByDevice( lul_device )
	-- D("actionSonosNotifyZoneGroupTopologyChange(%1,%2)", lul_device, lul_settings)
	D("actionSonosNotifyZoneGroupTopologyChange(%1, lul_settings) uuid is %2", lul_device, uuid)
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	assert( uuid ~= nil )
	assert( EventSubscriptions[uuid] ~= nil )
	if getVarNumeric( "MasterRole", 0, lul_device, SONOS_ZONE_SID ) == 0 then
		W("actionSonosNotifyZoneGroupTopologyChange() ignoring zone topology update for %1 (#%2): zone is not master role",
			luup.devices[lul_device].description, lul_device)
		setData("ZoneGroupState", "", uuid, false)
		return 4,0
	end
	if (upnp.isValidNotification("NotifyZoneGroupTopologyChange", lul_settings.sid, EventSubscriptions[uuid])) then
		local groupsState = lul_settings.ZoneGroupState or error("Missing ZoneGroupState")

		updateZoneInfo( groupsState )
		return 4,0
	end
	return 2,0
end

function actionSonosNotifyContentDirectoryChange( lul_device, lul_settings )
	local uuid = findZoneByDevice( lul_device )
	-- D("actionSonosNotifyContentDirectoryChange(%1,%2)", lul_device, lul_settings)
	D("actionSonosNotifyContentDirectoryChange(%1, lul_settings) uuid %2", lul_device, uuid)
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	assert( uuid ~= nil )
	assert( EventSubscriptions[uuid] ~= nil )
	if (upnp.isValidNotification("NotifyContentDirectoryChange", lul_settings.sid, EventSubscriptions[uuid])) then
		handleContentDirectoryChange(lul_device, uuid, lul_settings.ContainerUpdateIDs or "")
		return 4,0
	end
	return 2,0
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:micasaverde-com:serviceId:Volume1

--]]

function actionVolumeMute( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	-- Toggle Mute
	local uuid = findZoneByDevice( lul_device )
	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local channel = defaultValue(lul_settings, "Channel", "Master")

	local isMuted = tostring( dataTable[uuid].Mute or 0 ) ~= "0"
	local desiredMute = isMuted and 0 or 1

	Rendering.SetMute(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "DesiredMute=" .. desiredMute}})

	refreshMuteNow(uuid)
	return 4,0
end

function actionVolumeUp( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	-- Volume up
	local uuid = findZoneByDevice( lul_device )
	if tostring(dataTable[uuid].OutputFixed or 0) ~= "0" then
		L("Can't change volume on fixed output zone %1 (#%2)", luup.devices[lul_device].description, lul_device)
		return 4,0
	end

	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local channel = defaultValue(lul_settings, "Channel", "Master")

	Rendering.SetRelativeVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "Adjustment=3"}})

	refreshVolumeNow(uuid)
	return 4,0
end

function actionVolumeDown( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	-- Volume down
	local uuid = findZoneByDevice( lul_device )
	if tostring(dataTable[uuid].OutputFixed or 0) ~= "0" then
		W("Can't change volume on fixed output zone %1 (#%2)", luup.devices[lul_device].description, lul_device)
		return 4,0 -- OK
	end

	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local channel = defaultValue(lul_settings, "Channel", "Master")

	Rendering.SetRelativeVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "Adjustment=-3"}})

	refreshVolumeNow(uuid)
	return 4,0
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:micasaverde-com:serviceId:MediaNavigation1

--]]

function actionMediaNavigationSkipDown( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator( findZoneByDevice( lul_device ) )
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Next({InstanceID=instanceId})

	updateNow( device )
	return 4,0
end

function actionMediaNavigationSkipUp( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Previous({InstanceID=instanceId})

	updateNow( device )
	return 4,0
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:upnp-org:serviceId:AVTransport

--]]

function actionAVTransportPlayMedia( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local speed = defaultValue(lul_settings, "Speed", "1")

	AVTransport.Play(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"Speed=" ..speed}})

	updateNow( device )
	return 4,0
end

function actionAVTransportSeek( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local unit = defaultValue(lul_settings, "Unit", "")
	local target = defaultValue(lul_settings, "Target", "")

	AVTransport.Seek(
		{OrderedArgs={"InstanceID=" ..instanceId,
					"Unit=" .. unit,
					"Target=" .. target}})
	return 4,0
end

function actionAVTransportPause( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Pause({InstanceID=instanceId})

	updateNow( device )
	return 4,0
end

function actionAVTransportStop( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)

	local device, uuid
	uuid = findZoneByDevice( lul_device )
	if not ( isOnline(uuid) or setup(lul_device, true) ) then
		W("%1 (#%2) is offline and cannot be started", luup.devices[lul_device].description, lul_device)
		return 2,0
	end

	device, uuid = controlByCoordinator(uuid)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Stop({InstanceID=instanceId})

	updateNow( device )
	return 4,0
end

function actionAVTransportNext( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Next({InstanceID=instanceId})

	updateNow( device )
	return 4,0
end

function actionAVTransportPrevious( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Previous({InstanceID=instanceId})

	updateNow( device )
	return 4,0
end

function actionAVTransportNextSection( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.NextSection({InstanceID=instanceId})

	updateNow( device )
	return 4,0
end

function actionAVTransportPreviousSection( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.PreviousSection({InstanceID=instanceId})

	updateNow( device )
	return 4,0
end

function actionAVTransportNextProgrammedRadioTracks( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.NextProgrammedRadioTracks{InstanceID=instanceId}

	updateNow( device )
	return 4,0
end

function actionAVTransportGetPositionInfo( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	local _, tmp = AVTransport.GetPositionInfo{InstanceID=instanceId}
	setData("RelativeTimePosition", upnp.extractElement("RelTime", tmp, "NOT_IMPLEMENTED"), uuid, false)
	return 4,0
end

function actionAVTransportSetPlayMode( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local newPlayMode = defaultValue(lul_settings, "NewPlayMode", "NORMAL")

	-- NORMAL, SHUFFLE, SHUFFLE_NOREPEAT, REPEAT_ONE, REPEAT_ALL, RANDOM, DIRECT_1, INTRO
	AVTransport.SetPlayMode(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"NewPlayMode=" .. newPlayMode}})
	return 4,0
end

function actionAVTransportSetURI( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(findZoneByDevice( lul_device ), UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local currentURI = defaultValue(lul_settings, "CurrentURI", "")
	local currentURIMetaData = defaultValue(lul_settings, "CurrentURIMetaData", "")

	AVTransport.SetAVTransportURI(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"CurrentURI=" .. currentURI,
						"CurrentURIMetaData=" .. currentURIMetaData}})

	updateNow( lul_device )
	return 4,0
end

function actionAVTransportSetNextURI( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(findZoneByDevice( lul_device ), UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local nextURI = defaultValue(lul_settings, "NextURI", "")
	local nextURIMetaData = defaultValue(lul_settings, "NextURIMetaData", "")

	AVTransport.SetNextAVTransportURI(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"NextURI=" .. nextURI,
						"NextURIMetaData=" .. nextURIMetaData}})
	return 4,0
end

function actionAVTransportAddMultipleURIs( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local updateID = defaultValue(lul_settings, "UpdateID", "")
	local numberOfURIs = defaultValue(lul_settings, "NumberOfURIs", "")
	local enqueuedURIs = defaultValue(lul_settings, "EnqueuedURIs", "")
	local enqueuedURIsMetaData = defaultValue(lul_settings, "EnqueuedURIsMetaData", "")
	local containerURI = defaultValue(lul_settings, "ContainerURI", "")
	local containerMetaData = defaultValue(lul_settings, "ContainerMetaData", "")
	local desiredFirstTrackNumberEnqueued = defaultValue(lul_settings, "DesiredFirstTrackNumberEnqueued", 1)
	local enqueueAsNext = defaultValue(lul_settings, "EnqueueAsNext", true)

	AVTransport.AddMultipleURIsToQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"UpdateID=" .. updateID,
						"NumberOfURIs=" .. numberOfURIs,
						"EnqueuedURIs=" .. enqueuedURIs,
						"EnqueuedURIsMetaData=" .. enqueuedURIsMetaData,
						"ContainerURI=" .. containerURI,
						"ContainerMetaData=" .. containerMetaData,
						"DesiredFirstTrackNumberEnqueued=" .. desiredFirstTrackNumberEnqueued,
						"EnqueueAsNext=" .. enqueueAsNext}})
	return 4,0
end

function actionAVTransportAddURI( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local enqueuedURI = defaultValue(lul_settings, "EnqueuedURI", "")
	local enqueuedURIMetaData = defaultValue(lul_settings, "EnqueuedURIMetaData", "")
	local desiredFirstTrackNumberEnqueued = defaultValue(lul_settings, "DesiredFirstTrackNumberEnqueued", 1)
	local enqueueAsNext = defaultValue(lul_settings, "EnqueueAsNext", true)

	AVTransport.AddURIToQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"EnqueuedURI=" .. enqueuedURI,
						"EnqueuedURIMetaData=" .. enqueuedURIMetaData,
						"DesiredFirstTrackNumberEnqueued=" .. desiredFirstTrackNumberEnqueued,
						"EnqueueAsNext=" .. enqueueAsNext}})
	return 4,0
end

function actionAVTransportCreateSavedQueue( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local title = defaultValue(lul_settings, "Title", "")
	local enqueuedURI = defaultValue(lul_settings, "EnqueuedURI", "")
	local enqueuedURIMetaData = defaultValue(lul_settings, "EnqueuedURIMetaData", "")

	AVTransport.CreateSavedQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"Title=" .. title,
						"EnqueuedURI=" .. enqueuedURI,
						"EnqueuedURIMetaData=" .. enqueuedURIMetaData}})
	return 4,0
end

function actionAVTransportAddURItoSaved( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local objectID = defaultValue(lul_settings, "ObjectID", "")
	local updateID = defaultValue(lul_settings, "UpdateID", "")
	local enqueuedURI = defaultValue(lul_settings, "EnqueuedURI", "")
	local enqueuedURIMetaData = defaultValue(lul_settings, "EnqueuedURIMetaData", "")
	local addAtIndex = defaultValue(lul_settings, "AddAtIndex", 1)

	AVTransport.AddURIToSavedQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"ObjectID=" .. objectID,
						"UpdateID=" .. updateID,
						"EnqueuedURI=" .. enqueuedURI,
						"EnqueuedURIMetaData=" .. enqueuedURIMetaData,
						"AddAtIndex=" .. addAtIndex}})
	return 4,0
end

function actionAVTransportReorderQueue( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.ReorderTracksInQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"StartingIndex=" .. lul_settings.StartingIndex,
						"NumberOfTracks=" .. lul_settings.NumberOfTracks,
						"InsertBefore=" .. lul_settings.InsertBefore,
						"UpdateID=" .. lul_settings.UpdateID}})
	return 4,0
end

function actionAVTransportReorderSaved( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.ReorderTracksInSavedQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"ObjectID=" .. lul_settings.ObjectID,
						"UpdateID=" .. lul_settings.UpdateID,
						"TrackList=" .. lul_settings.TrackList,
						"NewPositionList=" .. lul_settings.NewPositionList}})
	return 4,0
end

function actionAVTransportRemoveTrackFromQueue( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.RemoveTrackFromQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"ObjectID=" .. lul_settings.ObjectID,
						"UpdateID=" .. lul_settings.UpdateID}})
	return 4,0
end

function actionAVTransportRemoveTrackRangeFromQueue( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.RemoveTrackRangeFromQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"UpdateID=" .. lul_settings.UpdateID,
						"StartingIndex=" .. lul_settings.StartingIndex,
						"NumberOfTracks=" .. lul_settings.NumberOfTracks}})
	return 4,0
end

function actionAVTransportRemoveAllTracksFromQueue( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.RemoveAllTracksFromQueue({InstanceID=instanceId})
	return 4,0
end

function actionAVTransportSaveQueue( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.SaveQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"Title=" .. lul_settings.Title,
						"ObjectID=" .. lul_settings.ObjectID}})
	return 4,0
end

function actionAVTransportBackupQueue( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.BackupQueue({InstanceID=instanceId})
	return 4,0
end

function actionAVTransportChangeTransportSettings( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.ChangeTransportSettings(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"NewTransportSettings=" .. lul_settings.NewTransportSettings,
						"CurrentAVTransportURI=" .. lul_settings.CurrentAVTransportURI}})
	return 4,0
end

function actionAVTransportConfigureSleepTimer( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(findZoneByDevice( lul_device ), UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.ConfigureSleepTimer(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"NewSleepTimerDuration=" .. lul_settings.NewSleepTimerDuration}})
	return 4,0
end

function actionAVTransportRunAlarm( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(findZoneByDevice( lul_device ), UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.RunAlarm(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"AlarmID=" .. lul_settings.AlarmID,
						"LoggedStartTime=" .. lul_settings.LoggedStartTime,
						"Duration=" .. lul_settings.Duration,
						"ProgramURI=" .. lul_settings.ProgramURI,
						"ProgramMetaData=" .. lul_settings.ProgramMetaData,
						"PlayMode=" .. lul_settings.PlayMode,
						"Volume=" .. lul_settings.Volume,
						"IncludeLinkedZones=" .. lul_settings.IncludeLinkedZones}})
	return 4,0
end

function actionAVTransportStartAutoplay( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.StartAutoplay(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"ProgramURI=" .. lul_settings.ProgramURI,
						"ProgramMetaData=" .. lul_settings.ProgramMetaData,
						"Volume=" .. lul_settings.Volume,
						"IncludeLinkedZones=" .. lul_settings.IncludeLinkedZones,
						"ResetVolumeAfter=" .. lul_settings.ResetVolumeAfter}})
	return 4,0
end

function actionAVTransportSnoozeAlarm( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(findZoneByDevice( lul_device ), UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.SnoozeAlarm(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"Duration=" .. lul_settings.Duration}})
	return 4,0
end

function actionAVTransportSetCrossfadeMode( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local desiredMode = tonumber(defaultValue(lul_settings, "CrossfadeMode", nil))

	-- If parameter is nill, we consider the callback as a toggle
	if (desiredMode == nil and device ~= 0) then
		local currentMode = luup.variable_get(UPNP_AVTRANSPORT_SID, "CurrentCrossfadeMode", device)
		desiredMode = 1 - (tonumber(currentMode) or 0)
	end

	AVTransport.SetCrossfadeMode(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"CrossfadeMode=" .. desiredMode}})

	updateNow( device )
	return 4,0
end

function actionAVTransportNotifyDeletedURI( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(findZoneByDevice( lul_device ), UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.NotifyDeletedURI(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"DeletedURI=" .. lul_settings.DeletedURI}})
	return 4,0
end

function actionAVTransportBecomeCoordinatorSG( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(findZoneByDevice( lul_device ), UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID=instanceId})
	return 4,0
end

function actionAVTransportBecomeGroupCoordinator( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(findZoneByDevice( lul_device ), UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.BecomeGroupCoordinator(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"CurrentCoordinator=" .. lul_settings.CurrentCoordinator,
						"CurrentGroupID=" .. lul_settings.CurrentGroupID,
						"OtherMembers=" .. lul_settings.OtherMembers,
						"TransportSettings=" .. lul_settings.TransportSettings,
						"CurrentURI=" .. lul_settings.CurrentURI,
						"CurrentURIMetaData=" .. lul_settings.CurrentURIMetaData,
						"SleepTimerState=" .. lul_settings.SleepTimerState,
						"AlarmState=" .. lul_settings.AlarmState,
						"StreamRestartState=" .. lul_settings.StreamRestartState,
						"CurrentQueueTrackList=" .. lul_settings.CurrentQueueTrackList}})
	return 4,0
end

function actionAVTransportBecomeGCAndSource( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(findZoneByDevice( lul_device ), UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.BecomeGroupCoordinatorAndSource(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"CurrentCoordinator=" .. lul_settings.CurrentCoordinator,
						"CurrentGroupID=" .. lul_settings.CurrentGroupID,
						"OtherMembers=" .. lul_settings.OtherMembers,
						"CurrentURI=" .. lul_settings.CurrentURI,
						"CurrentURIMetaData=" .. lul_settings.CurrentURIMetaData,
						"SleepTimerState=" .. lul_settings.SleepTimerState,
						"AlarmState=" .. lul_settings.AlarmState,
						"StreamRestartState=" .. lul_settings.StreamRestartState,
						"CurrentAVTTrackList=" .. lul_settings.CurrentAVTrackList,
						"CurrentQueueTrackList=" .. lul_settings.CurrentAVTTrackList,
						"CurrentSourceState=" .. lul_settings.CurrentSourceState,
						"ResumePlayback=" .. lul_settings.ResumePlayback}})
	return 4,0
end

function actionAVTransportChangeCoordinator( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(findZoneByDevice( lul_device ), UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.ChangeCoordinator(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"CurrentCoordinator=" .. lul_settings.CurrentCoordinator,
						"NewCoordinator=" .. lul_settings.NewCoordinator,
						"NewTransportSettings=" .. lul_settings.NewTransportSettings}})
	return 4,0
end

function actionAVTransportDelegateGCTo( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(findZoneByDevice( lul_device ), UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.DelegateGroupCoordinationTo(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"NewCoordinator=" .. lul_settings.NewCoordinator,
						"RejoinGroup=" .. lul_settings.RejoinGroup}})
	return 4,0
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:upnp-org:serviceId:RenderingControl

--]]

function actionRCSetMute( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local uuid = findZoneByDevice( lul_device )
	if not ( isOnline(uuid) or setup(lul_device, true) ) then
		W("%1 (#%2) is offline and cannot be started", luup.devices[lul_device].description, lul_device)
		return 2,0
	end

	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local desiredMute = defaultValue(lul_settings, "DesiredMute", false)
	local channel = defaultValue(lul_settings, "Channel", "Master")

	-- If parameter is nill, we consider the callback as a toggle
	if not desiredMute then
		local isMuted = tostring( dataTable[uuid].Mute or 0 ) ~= "0"
		desiredMute = isMuted and 0 or 1
	end

	Rendering.SetMute(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "DesiredMute=" .. desiredMute}})

	refreshMuteNow(uuid)
	return 4,0
end

function actionRCResetBasicEQ( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(findZoneByDevice( lul_device ), UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.ResetBasicEQ({InstanceID=instanceId})
	return 4,0
end

function actionRCResetExtEQ( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(findZoneByDevice( lul_device ), UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.ResetExtEQ(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "EQType=" .. lul_settings.EQType}})
	return 4,0
end

function actionRCSetVolume( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local uuid = findZoneByDevice( lul_device )
	if tostring(dataTable[uuid].OutputFixed or 0) ~= "0" then
		W("SetVolume on %1 (#%2) not possible, configured for fixed output volume (action ignored)",
			luup.devices[lul_device].description, lul_device)
		return 4,0 -- OK
	end

	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local desiredVolume = tonumber(defaultValue(lul_settings, "DesiredVolume", "5"))
	local channel = defaultValue(lul_settings, "Channel", "Master")

	Rendering.SetVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "DesiredVolume=" .. desiredVolume}})

	refreshVolumeNow(uuid)
	return 4,0
end

function actionRCSetRelativeVolume( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local uuid = findZoneByDevice( lul_device )
	if tostring(dataTable[uuid].OutputFixed or 0) ~= "0" then
		W("SetRelativeVolume on %1 (#%2) not possible, configured for fixed output volume (action ignored)",
			luup.devices[lul_device].description, lul_device)
		return 4,0 -- OK
	end

	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local channel = defaultValue(lul_settings, "Channel", "Master")

	Rendering.SetRelativeVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "Adjustment=" .. lul_settings.Adjustment}})

	refreshVolumeNow(uuid)
	return 4,0
end

function actionRCSetVolumeDB( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local uuid = findZoneByDevice( lul_device )
	if tostring(dataTable[uuid].OutputFixed or 0) ~= "0" then
		W("SetVolumeDB on %1 (#%2) not possible, configured for fixed output volume (action ignored)",
			luup.devices[lul_device].description, lul_device)
		return 4,0 -- OK
	end

	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local channel = defaultValue(lul_settings, "Channel", "Master")
	local desiredVolume = defaultValue(lul_settings, "DesiredVolume", "0")

	Rendering.SetVolumeDB(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "DesiredVolume=" .. desiredVolume}})

	refreshVolumeNow(uuid)
end

function actionRCSetBass( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(findZoneByDevice( lul_device ), UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetBass(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "DesiredBass=" .. lul_settings.DesiredBass}})
	return 4,0
end

function actionRCSetTreble( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(findZoneByDevice( lul_device ), UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetTreble(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "DesiredTreble=" .. lul_settings.DesiredTreble}})
	return 4,0
end

function actionRCSetEQ( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(findZoneByDevice( lul_device ), UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetEQ(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "EQType=" .. lul_settings.EQType,
					 "DesiredValue=" .. lul_settings.DesiredValue}})
	return 4,0
end

function actionRCSetLoudness( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(findZoneByDevice( lul_device ), UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetLoudness(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. lul_settings.Channel,
					 "DesiredLoudness=" .. lul_settings.DesiredLoudness}})
	return 4,0
end

function actionRCSetOutputFixed( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(findZoneByDevice( lul_device ), UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetOutputFixed(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "DesiredFixed=" .. lul_settings.DesiredFixed}})
	return 4,0
end

function actionRCRampToVolume( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(findZoneByDevice( lul_device ), UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.RampToVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. lul_settings.Channel,
					 "RampType=" .. lul_settings.RampType,
					 "DesiredVolume=" .. lul_settings.DesiredVolume,
					 "ResetVolumeAfter=" .. lul_settings.ResetVolumeAfter,
					 "ProgramURI=" .. lul_settings.ProgramURI}})
	return 4,0
end

function actionRCRestoreVolumePriorToRamp( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(findZoneByDevice( lul_device ), UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.RestoreVolumePriorToRamp(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. lul_settings.Channel}})

	return 4,0
end

function actionRCSetChannelMap( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(findZoneByDevice( lul_device ), UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetChannelMap(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "ChannelMap=" .. lul_settings.ChannelMap}})
	return 4,0
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:upnp-org:serviceId:GroupRenderingControl

--]]

function actionGRCSetGroupMute( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local GroupRendering = upnp.getService(uuid, UPNP_GROUP_RENDERING_CONTROL_SERVICE)
	if not GroupRendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local desiredMute = defaultValue(lul_settings, "DesiredMute", "0")

	GroupRendering.SetGroupMute(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "DesiredMute=" .. desiredMute}})
	return 4,0
end

function actionGRCSetGroupVolume( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local GroupRendering = upnp.getService(uuid, UPNP_GROUP_RENDERING_CONTROL_SERVICE)
	if not GroupRendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local desiredVolume = tonumber(defaultValue(lul_settings, "DesiredVolume", "5"))

	GroupRendering.SetGroupVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "DesiredVolume=" .. desiredVolume}})
	return 4,0
end

function actionGRCSetRelativeGroupVolume( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local GroupRendering = upnp.getService(uuid, UPNP_GROUP_RENDERING_CONTROL_SERVICE)
	if not GroupRendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	GroupRendering.SetRelativeGroupVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Adjustment=" .. lul_settings.Adjustment}})
	return 4,0
end

function actionGRCSnapshotGroupVolume( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(findZoneByDevice( lul_device ))
	local GroupRendering = upnp.getService(uuid, UPNP_GROUP_RENDERING_CONTROL_SERVICE)
	if not GroupRendering then
		return 2,0
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	GroupRendering.SnapshotGroupVolume(
		 {InstanceID=instanceId})
	return 4,0
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:micasaverde-com:serviceId:HaDevice1

--]]

function actionPoll( lul_device, lul_settings ) -- luacheck: ignore 212
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	updateNow(lul_device)
	return 4,0
end

--[[

	Request handler (http://vera-ip/port_3480/data_request?id=lr_Sonos&...

--]]

-- A "safer" JSON encode for Lua structures that may contain recursive references.
-- This output is intended for display ONLY, it is not to be used for data transfer.
local stringify
local function alt_json_encode( st, seen )
	seen = seen or {}
	str = "{"
	local comma = false
	for k,v in pairs(st) do
		str = str .. ( comma and "," or "" )
		comma = true
		str = str .. '"' .. k .. '":'
		if type(v) == "table" then
			if seen[v] then str = str .. '"(recursion)"'
			else
				seen[v] = k
				str = str .. alt_json_encode( v, seen )
			end
		else
			str = str .. stringify( v, seen )
		end
	end
	str = str .. "}"
	return str
end

-- Stringify a primitive type
stringify = function( v, seen )
	if v == nil then
		return "(nil)"
	elseif type(v) == "number" or type(v) == "boolean" then
		return tostring(v)
	elseif type(v) == "table" then
		return alt_json_encode( v, seen )
	elseif type(v) == "string" then
		v = v:gsub("\n", "\\n"):gsub("\t", "\\t")
	end
	return string.format( "%q", tostring(v) )
end

function handleRequest( lul_request, lul_parameters, lul_outputformat )
	D("request(%1,%2,%3) luup.device=%4", lul_request, lul_parameters, lul_outputformat, luup.device)
	local action = lul_parameters['action'] or lul_parameters['command'] or ""
	-- local deviceNum = tonumber( lul_parameters['device'] )
	if action == "debug" then
		local mode = tonumber(lul_parameters.debug) or 0
		setDebugLogs( mode )
		return string.format("OK\nDebug is now 0x%x", mode), "text/plain"

	elseif action == "ttsengines" then
		local resp = { status=true, engines={} }
		local edata = tts.getEngines()
		for k,e in pairs( edata ) do
			resp.engines[k] = {
				id=k,
				name=e.title or k,
				options=e:getOptionMeta()
			}
		end
		return json.encode( resp ), "application/json"

	elseif action == "zoneinfo" then
		return json.encode( zoneInfo ), "application/json"

	elseif action == "status" then
		local st = {
			name=PLUGIN_NAME,
			plugin=PLUGIN_ID,
			version=PLUGIN_VERSION,
			configversion=_CONFIGVERSION,
			uiversion=_UIVERSION,
			MIN_UPNP_VERSION = MIN_UPNP_VERSION,
			MIN_TTS_VERSION = MIN_TTS_VERSION,
			UPNP_VERSION = (upnp or {}).VERSION,
			TTS_VERSION = (tts or {}).VERSION,
			TTSBasePath = TTSBasePath,
			TTSBaseURL = TTSBaseURL,
			TTSChime = TTSChime,
			author="Patrick H. Rigney (rigpapa)",
			url=PLUGIN_URL,
			['type']=SONOS_SYS_DEVICE_TYPE,
			responder=luup.device,
			timestamp=os.time(),
			system = {
				version=luup.version,
				short_version=luup.short_version,
				isOpenLuup=isOpenLuup,
				isALTUI=isALTUI,
				hardware=luup.attr_get("model",0),
				modelID=luup.modelID,
				lua=tostring((_G or {})._VERSION)
			},
			devices={}
		}
		local _,_,_,ra = luup.call_action( "urn:micasaverde-com:serviceId:HomeAutomationGateway1", "GetUserData", { DataFormat="json" }, 0 ) -- luacheck: ignore 311
		ra = tostring( ra.UserData )
		ra = json.decode( ra )
		if ra then
			for _,v in ipairs( ra.devices or {} ) do
				if v.device_type == SONOS_SYS_DEVICE_TYPE or v.device_type == SONOS_ZONE_DEVICE_TYPE
						or v.id_parent == pluginDevice then
					if v.id == pluginDevice then
						v.zoneInfo = zoneInfo
						v.Zones = Zones
						v.systemReady = systemReady
						v.metaDataKeys = metaDataKeys
						v.sonosServices = sonosServices
						v.tickTasks = scheduler.getOwnerTasks()
					end
					table.insert( st.devices, v )
				end
			end
			st.luup = {}
			st.luup.InstalledPlugins2 = ra.InstalledPlugins2
			for k,v in pairs( ra ) do
				if string.match( ":number:string:boolean:", type(v) ) then
					st.luup[k] = v
				end
			end
		end
		return alt_json_encode( st ), "application/json"

	elseif action == "files" then
		local st = {}
		local fd = { [getInstallPath()]=true, ["/etc/cmh-lu/"]=true, ["/etc/cmh/"]=true }
		fd[TTSBasePath] = true
		local function flist( dir, r )
			r = r or {}
			local f = io.popen( "ls -lR '"..dir.."'" )
			r[dir] = {}
			if f then
				repeat
					local line = f:read("*l")
					if line then table.insert( r[dir], line ) end
				until not line
				f:close()
			end
			return r
		end
		for d in pairs( fd ) do
			st = flist( d, st )
		end
		return alt_json_encode( st ), "application/json"

	else
		return "ERROR\nInvalid request action", "text/plain"
	end
end
