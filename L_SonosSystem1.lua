--[[
	Sonos Plugin for Vera and openLuup
	Current maintainer: rigpapa https://community.getvera.com/u/rigpapa/summary
	Github repository: https://github.com/toggledbits/Sonos-Vera
	For license information, please see the above repository.
--]]

module( "L_SonosSystem1", package.seeall )

PLUGIN_NAME = "Sonos"
PLUGIN_VERSION = "2.0-19345"
PLUGIN_ID = 4226

local _CONFIGVERSION = 19298

local DEBUG_MODE = false	-- Don't hardcode true--use state variable config

local MIN_UPNP_VERSION = 19191	-- Minimum version of L_SonosUPnP that works
local MIN_TTS_VERSION = 19287	-- Minimum version of L_SonosTTS that works

local MSG_CLASS = "Sonos"
local isOpenLuup = false
local pluginDevice

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

local url = require "socket.url"
local lom = require "lxp.lom"

-- Table of Sonos IP addresses indexed by Vera devices
local port = 1400
local descriptionURL = "http://%s:%s/xml/device_description.xml"
local iconURL = "../../icons/Sonos.png"

local HADEVICE_SID = "urn:micasaverde-com:serviceId:HaDevice1"
local SONOS_ZONE_SID = "urn:micasaverde-com:serviceId:Sonos1"
local SONOS_ZONE_DEVICE_TYPE = "urn:schemas-micasaverde-com:device:Sonos:1"
local SONOS_SYS_SID = "urn:toggledbits-com:serviceId:SonosSystem1"
local SONOS_SYS_DEVICE_TYPE = "urn:schemas-toggledbits-com:device:SonosSystem:1"

local EventSubscriptionsTemplate = {
	{
		service=UPNP_AVTRANSPORT_SERVICE,
		eventVariable="LastChange",
		actionName="NotifyAVTransportChange"
	},
	{
		service=UPNP_RENDERING_CONTROL_SERVICE,
		eventVariable="LastChange",
		actionName="NotifyRenderingChange"
	},
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
local zoneInfo = false
local groupsState = ""

local UUIDs = {} -- key is device, value is UUID
local Zones = {} -- key is UUID, value is device
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

	SavedQueues = UPNP_MR_CONTENT_DIRECTORY_SID,
	FavoritesRadios = UPNP_MR_CONTENT_DIRECTORY_SID,
	Favorites = UPNP_MR_CONTENT_DIRECTORY_SID,
	Queue = UPNP_MR_CONTENT_DIRECTORY_SID,

	GroupCoordinator = SONOS_ZONE_SID,
	ZonePlayerUUIDsInGroup = UPNP_ZONEGROUPTOPOLOGY_SID,
	ZoneGroupState = UPNP_ZONEGROUPTOPOLOGY_SID,

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
local TTS_METADATA = [[<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
	<item id="VERA_TTS" parentID="-1" restricted="1">
		<dc:title>%s</dc:title>
		<res protocolInfo="%s">%s</res>
		<upnp:class>object.item.audioItem.musicTrack</upnp:class>
	</item>
</DIDL-Lite>]]
local TTSChime

local scheduler

local function Q(str) return "'" .. string.gsub(tostring(str), "(')", "\\%1") .. "'" end

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

local function L(msg, ...) -- luacheck: ignore 212
	local str
	local level = defaultLogLevel or 50
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
	if level == 0 and debug and debug.traceback then luup.log( debug.traceback(), 1 ) error(str) end
end

local function W(msg, ...)
	L({msg=msg,level=2}, ...)
end

local function E(msg, ...)
	L({msg=msg,level=1}, ...)
end

local function D(msg, ...)
	if DEBUG_MODE then L({msg="[debug] "..msg, level=50}, ...) end
end

-- Clone table (shallow copy)
local function clone( sourceArray )
	local newArray = {}
	for ix,element in pairs( sourceArray or {} ) do
		newArray[ix] = element
	end
	return newArray
end

local function deepCopy( sourceArray )
	local newArray = {}
	for key,val in pairs( sourceArray or {} ) do
		if type(val) == "table" then
			newArray[key] = deepCopy( val )
		else
			newArray[key] = val
		end
	end
	return newArray
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

local function findDeviceByUUID( zoneUUID )
	return Zones[zoneUUID]
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

-- Return true if file exists; optionally returns handle to open file if exists.
local function file_exists( fpath, leaveOpen )
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

local function file_dtm( fpath )
	local f = io.popen( "stat -c %Y "..fpath )
	if not f then return 0 end
	local ts = tonumber( f:read("*a") ) or 0
	f:close()
	return ts
end

local function getInstallPath()
	if isOpenLuup then
		local loader = require "openLuup.loader"
		if loader.find_file == nil then
			W("This version of the Sonos plugin requires openLuup 2018.11.21 or higher")
			return "./" -- punt
		end
		return loader.find_file( "L_Sonos1.lua" ):gsub( "L_Sonos1.lua$", "" )
	end
	return "/etc/cmh-ludl/"
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
	return (arr or {})[val] or default
end

-- Set local and state variable data for zone. `zoneident` can be device number or zone UUID.
-- Every caller should use ident; the use of device number is deprecated.
local function setData(name, value, zoneident, default)
	local uuid = UUIDs[tonumber(zoneident) or -999] or zoneident
	if uuid then
if uuid == "RINCON_48A6B813879001400" and name == "OutputFixed" and value ~= "0" then L{msg="stop",level=0} end -- ??? FIXME
		-- The shadow table stores the value whether there's a device for the zone or not
		dataTable[uuid] = dataTable[uuid] or {}
		local curValue = dataTable[uuid][name]
		if value == nil or value ~= curValue then
			-- Use state variables as well for known devices
			dataTable[uuid][name] = value
			local device = Zones[uuid] or 0
			if device ~= 0 and variableSidTable[name] then
				setVar( variableSidTable[name], name, value == nil and "" or tostring(value), device )
			else
				D("No serviceId defined for %1; state variable value not saved", name);
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

--[[ currently unused
local function parseSimple(value, tag)
	local elts = {}
	local eltsTable = {}
	for tmp in value:gmatch("(<"..tag.."%s?.-</"..tag..">)") do
		local elts0, eltsTable0 = upnp.parseFirstElt(tmp, tag, nil)
		table.insert(elts, elts0)
		table.insert(eltsTable, eltsTable0)
	end

	return elts, eltsTable
end

local function getValueFromXML(xml, tag, subTag, value, tagResult)
	local result = nil
	local _, eltsTable = parseSimple(xml, tag)
	for _, v in ipairs(eltsTable) do
		if (v[subTag] == value and v[tagResult] ~= nil) then
			result = v[tagResult]
			break
		end
	end
	return result
end
--]]

local function getAttribute(xml, tag, attribute)
	local value = xml:match("<"..tag.."%s?.-%s"..attribute..'="([^"]+)"[^>]->')
	if (value ~= nil) then
		value = upnp.decode(value)
	end
	return value
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
function updateZoneInfo( uuid )
	D("updateZoneInfo(%1)", uuid)
	zoneInfo = { zones={}, groups={} }
	local zs = dataTable[uuid].ZoneGroupState
	-- D("updateZoneInfo() zone info is \r\n%1", tostring(zs))
	local root = lom.parse( zs )
	assert( root and root.tag == "ZoneGroupState" )
	local groups = xmlNodesForTag( root, "ZoneGroups" )()
	if not groups then return end -- probably no data yet
	for v in xmlNodesForTag( groups, "ZoneGroup" ) do
		local gr = { UUID=v.attr.ID, Coordinator=v.attr.Coordinator, members={} }
		zoneInfo.groups[v.attr.ID] = gr
		for v2 in xmlNodesForTag( v, "ZoneGroupMember" ) do
			local zi = {}
			for _,v3 in ipairs( v2.attr or {} ) do
				zi[v3] = tonumber( v2.attr[v3] ) or v2.attr[v3]
			end
			zi.Group = gr.UUID
			zoneInfo.zones[v2.attr.UUID] = zi
			table.insert( gr.members, v2.attr.UUID )
		end
	end
	D("updateZoneInfo() updated zoneInfo: %1", zoneInfo)
end

local function getZoneNameFromUUID(uuid)
	return (zoneInfo.zones[uuid] or {}).ZoneName
end

local function getUUIDFromZoneName(name)
	for _,item in pairs( zoneInfo.zones ) do
		if item.ZoneName == name then return item.UUID end
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
	if zi then
		D("getZoneGroup() group info for %1 is %2", zi.Group, zoneInfo.groups[zi.Group])
		return zoneInfo.groups[zi.Group]
	end
	W("No zoneInfo for zone %1", zoneUUID)
	return nil
end

local function getZoneCoordinator( zoneUUID )
	local gr = getZoneGroup( zoneUUID ) or {}
	return (gr or {}).Coordinator or zoneUUID, gr
end

-- Return true if zone is group coordinator
local function isGroupCoordinator( zoneUUID )
	local gr = getZoneGroup( zoneUUID ) or {}
	return zoneUUID == gr.Coordinator
end

-- Return group info for the group of which `uuid` is a member
local function getGroupInfos(uuid)
	local groupInfo = getZoneGroup( uuid ) or {}
	return table.concat( groupInfo.members or {}, "," ), groupInfo.Coordinator or "", groupInfo.ID
end

local function getAllUUIDs()
	local zones = {}
	for zid,zone in pairs( zoneInfo.zones ) do
		if zone.isZoneBridge ~= "1" then
			table.insert( zones, zid )
		end
	end
	return table.concat( zones, "," ), zones
end

-- Return bool if device is online; pass device number or zone uuid
local function isOnline(zone)
	local uuid = tonumber(zone) and UUIDs[zone] or zone
	if uuid and Zones[uuid] then
		return tostring(dataTable[uuid].SonosOnline or 0) ~= "0"
	end
	return false
end

local function deviceIsOnline(device)
	local changed = setData("SonosOnline", "1", UUIDs[device], false)
	if changed then
		L("Setting device #%1 on line", device)
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), device)
	end
	return changed
end

local function deviceIsOffline(device)
	local uuid = UUIDs[device]
	local changed = setData("SonosOnline", "0", uuid, false)
	if changed then
		W("Setting device #%1 to off-line state", device)
		groupsState = "<ZoneGroups></ZoneGroups>"

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
		changed = setData("SavedQueues", "", uuid, changed)
		changed = setData("FavoritesRadios", "", uuid, changed)
		changed = setData("Favorites", "", uuid, changed)
		changed = setData("Queue", "", uuid, changed)
		changed = setData("GroupCoordinator", "", uuid, changed)
		changed = setData("ZonePlayerUUIDsInGroup", "", uuid, changed)
		changed = setData("ZoneGroupState", groupsState, uuid, changed)
		updateZoneInfo( uuid )

		if changed and device ~= 0 then
			setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), device)
		end

		if EventSubscriptions[uuid] then
			upnp.cancelProxySubscriptions(EventSubscriptions[uuid])
			EventSubscriptions[uuid] = nil
		end
	end
end

local function commsFailure(device, text)
	W("Sonos %1 device #%2 (%3) at %4 comm failure. "..tostring(text or ""),
		UUIDs[device], device, (luup.devices[device] or {}).description,
		luup.attr_get("ip", device or -1) or "")
	deviceIsOffline(device)
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

local function updateServicesMetaDataKeys(uuid, id, key)
	if id ~= nil and key ~= "" and metaDataKeys[uuid][id] ~= key and (Zones[uuid] or 0) ~= 0 then
		metaDataKeys[uuid][id] = key
		local data = ""
		for k, v in pairs(metaDataKeys[uuid]) do
			data = data .. string.format('%s=%s\n', k, v)
		end
		setVariableValue(SONOS_ZONE_SID, "SonosServicesKeys", data, Zones[uuid])
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), Zones[uuid])
	end
end

local function loadServicesMetaDataKeys(device)
	local k = {}
	local elts = getVar("SonosServicesKeys", "", device, SONOS_ZONE_SID)
	for token, value in elts:gmatch("([^=]+)=([^\n]+)\n") do
		k[token] = value
	end
	return k
end

local function extractDataFromMetaData(zoneUUID, currentUri, currentUriMetaData, trackUri, trackUriMetaData)
	local statusString, info, title, title2, artist, album, details, albumArt, desc
	local uuid = zoneUUID
	_, title, _, _, _, _, desc = getSimpleDIDLStatus(currentUriMetaData)
	info, title2, artist, album, details, albumArt, _ = getSimpleDIDLStatus(trackUriMetaData)
	local service, serviceId = getServiceFromURI(currentUri, trackUri)
	updateServicesMetaDataKeys(zoneUUID, serviceId, desc)
	statusString = ""
	if (service ~= "") then
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
	if (albumArt ~= "") then
		local ip = luup.attr_get( "ip", Zones[uuid]) or ""
		albumArt = url.absolute(string.format("http://%s:%s/", ip, port), albumArt)
	elseif (serviceId ~= nil) then
		local ip = luup.attr_get( "ip", Zones[uuid]) or ""
		albumArt = string.format("http://%s:%s/getaa?s=1&u=%s", ip, port, url.escape(currentUri))
	else
		albumArt = iconURL
	end
	return service, title, statusString, title2, artist, album, details, albumArt
end

local function parseSavedQueues(xml)
	local result = ""
	for id, title in xml:gmatch('<container%s?.-id="([^"]-)"[^>]->.-<dc:title%s?[^>]->(.-)</dc:title>.-</container>') do
		id = upnp.decode(id)
		title = upnp.decode(title)
		result = result .. id .. "@" .. title .. "\n"
	end
	return result
end

--[[ currentl unused
local function parseFavoritesRadios(xml)
	local result = ""
	for title, res in xml:gmatch("<item%s?[^>]->.-<dc:title%s?[^>]->(.-)</dc:title>.-<res%s?[^>]->(.-)</res>.-</item>") do
		title = upnp.decode(title)
		result = result .. res .. "@" .. title .. "\n"
	end
	return result
end
--]]

local function parseIdTitle(xml)
	local result = ""
	for id, title in xml:gmatch('<item%s?.-id="([^"]-)"[^>]->.-<dc:title%s?[^>]->(.-)</dc:title>.-</item>') do
		id = upnp.decode(id)
		title = upnp.decode(title)
		result = result .. id .. "@" .. title .. "\n"
	end
	return result
end

local function parseQueue(xml)
	local result = ""
	for title in xml:gmatch("<item%s?[^>]->.-<dc:title%s?[^>]->(.-)</dc:title>.-</item>") do
		title = upnp.decode(title)
		result = result .. title .. "\n"
	end
	return result
end

-- Check transport state to see if stopped. If so and TTS alerts running, rush the endSayAlert
-- task for the device.
local function checkTransportState( uuid )
	D("checkTransportState(%1) state %2", uuid, (dataTable[uuid] or {}).TransportState)
	if dataTable[uuid].TransportState == "STOPPED" then
		local device = Zones[uuid]
		local task = scheduler.getTask("endSayAlert"..(device or 0))
		D("checkTransportState() device %1 task %2 queue %3", device, task, sayQueue[device])
		if device and task and sayQueue[device] then
			D("checkTransportState() stopped playing %1, waiting for %2",
				dataTable[uuid].CurrentTrackURI, sayQueue[device][1].URI)
			if dataTable[uuid].CurrentTrackURI == sayQueue[device][1].URI then
				D("refreshNow() rushing %1 for STOPPED transport status", tostring(task))
				task:delay( 0, { replace=true } )
			end
		end
	end
end

local setup -- forward declaration
-- refreshNow is the refresh handle for updateWithoutProxy (task). DO NOT call this function
-- directly. To get proper scheduling of refreshing, including on-demand refreshes, always
-- use updateNow()
local function refreshNow(uuid, force, refreshQueue)
	D("refreshNow(%1)", uuid, force, refreshQueue)
	if (uuid or "") == "" then
		return
	end
	local device = Zones[uuid]
	if (device or 0) == 0 then
		W("Can't refresh unknown zone %1; reload Luup to add this device.", uuid)
	end

	if upnp.proxyVersionAtLeast(1) and not force then
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

	-- Update network and group information
	local ZoneGroupTopology = upnp.getService(uuid, UPNP_ZONEGROUPTOPOLOGY_SERVICE)
	if ZoneGroupTopology then
		D("refreshNow() refreshing zone group topology")
		status, tmp = ZoneGroupTopology.GetZoneGroupState({})
		if not status then
			commsFailure(device, tmp)
			return ""
		end
		groupsState = upnp.extractElement("ZoneGroupState", tmp, "")
		changed = setData("ZoneGroupState", groupsState, uuid, changed)
		if changed or not zoneInfo then
			updateZoneInfo( uuid )
		end
		local members, coordinator = getGroupInfos( uuid )
		changed = setData("ZonePlayerUUIDsInGroup", members, uuid, changed)
		changed = setData("GroupCoordinator", coordinator or "", uuid, changed)
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
		local tschanged = setData("TransportState", upnp.extractElement("CurrentTransportState", tmp, ""), uuid, false)

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

		-- Now that we've updated everything, if TransportState has changed to stop, check
		if tschanged then
			changed = true
			checkTransportState( uuid )
		end

	end

	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if Rendering then
		D("refreshNow() refreshing rendering state")
		-- Get Mute status
		status, tmp = Rendering.GetMute({OrderedArgs={"InstanceID=0", "Channel=Master"}})
		if status ~= true then
			commsFailure(device, tmp)
			return ""
		end
		changed = setData("Mute", upnp.extractElement("CurrentMute", tmp, ""), uuid, changed)

		-- Get Volume
		status, tmp = Rendering.GetVolume({OrderedArgs={"InstanceID=0", "Channel=Master"}})
		if not status then
			commsFailure(device, tmp)
			return ""
		end
		changed = setData("Volume", upnp.extractElement("CurrentVolume", tmp, ""), uuid, changed)

		-- Get Bass
		status, tmp = Rendering.GetBass({OrderedArgs={"InstanceID=0", "Channel=Master"}})
		if status ~= true then
			commsFailure(device, tmp)
			return ""
		end
		changed = setData("Bass", upnp.extractElement("CurrentBass", tmp, ""), uuid, changed)

		-- Get Treble
		status, tmp = Rendering.GetTreble({OrderedArgs={"InstanceID=0", "Channel=Master"}})
		if status ~= true then
			commsFailure(device, tmp)
			return ""
		end
		changed = setData("Treble", upnp.extractElement("CurrentTreble", tmp, ""), uuid, changed)

		-- Get Loudness
		status, tmp = Rendering.GetLoudness({OrderedArgs={"InstanceID=0", "Channel=Master"}})
		if status ~= true then
			commsFailure(device, tmp)
			return ""
		end
		changed = setData("Loudness", upnp.extractElement("CurrentLoudness", tmp, ""), uuid, changed)

		-- Get OutputFixed
		status, tmp = Rendering.GetOutputFixed({OrderedArgs={"InstanceID=0"}})
		if status ~= true then
			commsFailure(device, tmp)
			return ""
		end
		changed = setData("OutputFixed", upnp.extractElement("CurrentFixed", tmp, ""), uuid, changed)
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

	if upnp.proxyVersionAtLeast(1) and not force then
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
		commsFailure(Zones[uuid], tmp)
		return
	end

	changed = setData("Volume", upnp.extractElement("CurrentVolume", tmp, ""), uuid, false)

	if changed and Zones[uuid] ~= 0 then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), Zones[uuid])
	end
end

local function refreshMuteNow(uuid)
	D("refreshMuteNow(%1)", uuid)

	if upnp.proxyVersionAtLeast(1) then
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
		commsFailure(Zones[uuid], tmp)
		return
	end

	changed = setData("Mute", upnp.extractElement("CurrentMute", tmp, ""), uuid, false)

	if changed and Zones[uuid] then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), Zones[uuid])
	end
end

local function updateWithoutProxy(task, device)
	D("updateWithoutProxy(%1,%2)", tostring(task), device)
	local uuid = UUIDs[device]
	refreshNow(uuid, true, true)
	if not upnp.proxyVersionAtLeast(1) then
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
		task:delay( (ts == "STOPPED" or not isGroupCoordinator(uuid)) and rs or rp )
		D("Scheduled update for no proxy, state %1", ts)
		return
	else
		-- Not reschedulling, but leave task
	end
	D("Proxy found, skipping poll reschedule")
end

local function updateNow(device)
	if UUIDs[device] then
		local task = scheduler.getTask("update"..device) or scheduler.Task:new( "update"..device, device, updateWithoutProxy, { device } )
		task:delay(0, { replace=true } )
	end
end

local function controlAnotherZone(targetUUID, sourceUUID)
	return targetUUID
end

local function controlByCoordinator(uuid)
	local gr = getZoneGroup( uuid )
	if gr then
		uuid = gr.Coordinator or uuid
	end
	return findDeviceByUUID( uuid ) or 0, uuid
end

-- ??? rigpapa: there is brokenness in the handling of the title variable throughout,
--              with interior local redeclarations shadowing the exterior declaration, it's unclear
--              if the inner values attained are needed in the outer scopes. This needs
--              to be studied carefully before cleanup.
local function decodeURI(localUUID, coordinator, uri)
	D("decodeURI(%1,%2,%3)", localUUID, coordinator, uri)
	local uuid = nil
	local track = nil
	local uriMetaData = ""
	local serviceId
	local title = nil
	local controlByGroup = true
	local requireQueueing = false

	if uri:sub(1, 2) == "Q:" then
		track = uri:sub(3)
		uri = QUEUE_URI:format(coordinator)
	elseif uri:sub(1, 3) == "AI:" then
		if #uri > 3 then
			uuid = getUUIDFromZoneName(uri:sub(4))
		else
			uuid = localUUID
		end
		if uuid ~= nil then
			uri = "x-rincon-stream:" .. uuid
		else
			uri = nil
		end
	elseif uri:sub(1, 3) == "SQ:" then
		local found = false
		if dataTable[localUUID].SavedQueues ~= nil then
			local id, title
			for line in dataTable[localUUID].SavedQueues:gmatch("(.-)\n") do
				id, title = line:match("^(.+)@(.-)$")
				if (id ~= nil and title == uri:sub(4)) then
					found = true
					uri = "ID:" .. id
					break
				end
			end
		end
		if found == false then
			uri = nil
		end
	elseif uri:sub(1, 3) == "FR:" then
		title = uri:sub(4)
		local found = false
		if dataTable[localUUID].FavoritesRadios ~= nil then
			local id, title
			for line in dataTable[localUUID].FavoritesRadios:gmatch("(.-)\n") do
				id, title = line:match("^(.+)@(.-)$")
				if id ~= nil and title == uri:sub(4) then
					found = true
					uri = "ID:" .. id
					break
				end
			end
		end
		if found == false then
			uri = nil
		end
	elseif uri:sub(1, 3) == "SF:" then
		title = uri:sub(4)
		local found = false
		if dataTable[localUUID].Favorites ~= nil then
			local id, title
			for line in dataTable[localUUID].Favorites:gmatch("(.-)\n") do
				id, title = line:match("^(.+)@(.-)$")
				if (id ~= nil and title == uri:sub(4)) then
					found = true
					uri = "ID:" .. id
					break
				end
			end
		end
		if found == false then
			uri = nil
		end
	elseif uri:sub(1, 3) == "TR:" then
		title = uri:sub(4)
		serviceId = getSonosServiceId("TuneIn") or "254"
		uri = "x-sonosapi-stream:s" .. uri:sub(4) .. "?sid=" .. serviceId .. "&flags=32"
	elseif uri:sub(1, 3) == "SR:" then
		title = uri:sub(4)
		serviceId = getSonosServiceId("SiriusXM") or "37"
		uri = "x-sonosapi-hls:r%3a" .. title .. "?sid=" .. serviceId .. "&flags=288"
	elseif uri:sub(1, 3) == "GZ:" then
		controlByGroup = false
		if (#uri > 3) then
			uuid = getUUIDFromZoneName(uri:sub(4))
		end
		if uuid ~= nil then
			uri = "x-rincon:" .. uuid
		else
			uri = nil
		end
	end

	if uri:sub(1, 3) == "ID:" then
		local xml = upnp.browseContent(localUUID, UPNP_MR_CONTENT_DIRECTORY_SERVICE, uri:sub(4), true, nil, nil, nil)
		D("data from server:\r\n%1", xml)
		if xml == "" then
			uri = nil
		else
			title, uri = xml:match("<DIDL%-Lite%s?[^>]-><item%s?[^>]->.-<dc:title%s?[^>]->(.-)</dc:title>.-<res%s?[^>]->(.*)</res>.-</item></DIDL%-Lite>")
			if uri ~= nil then
				uriMetaData = upnp.decode(xml:match("<DIDL%-Lite%s?[^>]-><item%s?[^>]->.-<r:resMD%s?[^>]->(.*)</r:resMD>.-</item></DIDL%-Lite>") or "")
			else
				title, uri = xml:match("<DIDL%-Lite%s?[^>]-><container%s?[^>]->.-<dc:title%s?[^>]->(.-)</dc:title>.-<res%s?[^>]->(.*)</res>.-</container></DIDL%-Lite>")
				if uri ~= nil then
					uriMetaData = upnp.decode(xml:match("<DIDL%-Lite%s?[^>]-><container%s?[^>]->.-<r:resMD%s?[^>]->(.*)</r:resMD>.-</container></DIDL%-Lite>") or "")
				end
			end
		end
	end

	if uri ~= nil and
		   (uri:sub(1, 38) == "file:///jffs/settings/savedqueues.rsq#"
			   or uri:sub(1, 18) == "x-rincon-playlist:"
			   or uri:sub(1, 21) == "x-rincon-cpcontainer:") then
		requireQueueing = true
	end

	if uri ~= nil and uri ~= "" and uriMetaData == "" then
		_, serviceId = getServiceFromURI(uri, nil)
		if serviceId ~= nil and metaDataKeys[localUUID][serviceId] ~= nil then
			if title == nil then
				uriMetaData = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
							  .. '<item><desc>' .. metaDataKeys[localUUID][serviceId] .. '</desc>'
							  .. '</item></DIDL-Lite>'
			else
				uriMetaData = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
							  .. '<item><dc:title>' .. title .. '</dc:title>'
							  .. '<desc>' .. metaDataKeys[localUUID][serviceId] .. '</desc>'
							  .. '</item></DIDL-Lite>'
			end
		elseif title ~= nil then
			uriMetaData = '<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">'
						  .. '<item><dc:title>' .. title .. '</dc:title>'
						  .. '<upnp:class>object.item.audioItem.audioBroadcast</upnp:class>'
						  .. '</item></DIDL-Lite>'
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
	local coordinator = getZoneCoordinator( zoneUUID )
	if controlByGroup then
		uuid = coordinator
	end

	uri, uriMetaData, track, controlByGroup2, requireQueueing = decodeURI(uuid, coordinator, uri)
	if (controlByGroup and not controlByGroup2) then
		-- ??? rigpapa ...and then what are the controlByGroup variables used for???
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
					local device = Zones[uuid]
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
	for _,uuid in ipairs( uuids ) do
		if controlAnotherZone(uuid, UUIDs[device]) then
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
	-- local localUUID = UUIDs[device]
	-- local device2

	if not playCxt then
		-- W("Please save the context before restoring it!")
		return
	end

	-- Find coordinators and restore context
	for uuid, zone in pairs( playCxt.context ) do
		if zone.GroupCoordinator == uuid then
			restorePlaybackContext( zone.Device or 0, uuid, zone )
		end
	end

	-- Finally restore context for other zones -- ??? PHR do we need to? or is restoring coordinator sufficient? easy to test...
	for uuid, cxt in pairs(playCxt.context) do
		if cxt.GroupCoordinator ~= uuid then
			restorePlaybackContext(cxt.Device or 0, uuid, cxt)
		end
	end
end

-- The device is added to the same group as zone (UUID or name)
local function joinGroup(localUUID, zone)
	local uuid = zone:match("RINCON_%x+") and zone or getUUIDFromZoneName(zone)
	if uuid ~= nil and zoneInfo.zones[uuid] then
		local groupInfo = zoneInfo.groups[zoneInfo.zones[uuid].Group]
		for _,member in ipairs( (groupInfo or {}).members or {} ) do
			if member.UUID == localUUID then return end -- already in group
		end
		playURI(localUUID, "0", "x-rincon:" .. groupInfo.Coordinator, "1", nil, nil, false, nil, false, false)
	end
end

local function leaveGroup(localUUID)
	local AVTransport = upnp.getService(localUUID, UPNP_AVTRANSPORT_SERVICE)
	if AVTransport ~= nil then
		AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID="0"})
	end
end

local function updateGroupMembers(gc, members)
	local prevMembers, coordinator = getGroupInfos(gc)
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

	-- Make any new members part of the group
	for uuid in pairs( targetMap ) do
		if not prevMembers:find(uuid) then
			playURI(uuid, "0", "x-rincon:" .. coordinator, "1", nil, nil, false, nil, false, false)
		end
	end

	-- Remove previous members that are no longer in group
	for uuid in prevMembers:gmatch("RINCON_%x+") do
		if not targetMap[uuid] then
			if controlAnotherZone(uuid, gc) then
				local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
				if AVTransport then
					AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID="0"})
				end
			end
		end
	end
end

local function pauseAll(device)
	local localUUID = UUIDs[device]
	local _, uuids = getAllUUIDs()
	for uuid in ipairs( uuids ) do
		if controlAnotherZone(uuid, localUUID) then
			local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
			if AVTransport then
				AVTransport.Pause({InstanceID="0"})
			end
		end
	end
end

local function getMP3Duration( mp3file, bitrate )
	if not bitrate then
		local fp = io.popen("file "..mp3file)
		if fp then
			local s = fp.read("*l")
			fp:close()
			bitrate = tonumber( s:match( '(%d+)kbps' ) or "" ) or 32
		else
			bitrate = 32
		end
	end
	local f = io.open( mp3file, "r" )
	if f then
		local sz = f:seek("end")
		f:close()
		return math.ceil(sz * 8 / ( bitrate * 1024 ) )
	end
	return 2 -- ugly default
end

local function setupTTSSettings(device)
	if not tts then return end
	assert(luup.devices[device].device_type == SONOS_SYS_DEVICE_TYPE)
	local ttsrev = getVarNumeric("_ttsrev", 0, device, SONOS_SYS_SID)
	local lang = getVar("DefaultLanguageTTS", "", device, SONOS_SYS_SID, true)
	if lang == "" then
		lang = "en"
	elseif lang == "en" then
		setVar(SONOS_SYS_SID, "DefaultLanguageTTS", "", device) -- restore default
	end
	local engine = getVar("DefaultEngineTTS", "", device, SONOS_SYS_SID, true)
	if engine == "" then
		engine = "GOOGLE"
	elseif engine == "GOOGLE" then
		setVar(SONOS_SYS_SID, "DefaultEngineTTS", "", device) -- restore default
	end
	local googleURL = getVar("GoogleTTSServerURL", "", device, SONOS_SYS_SID, true)
	if googleURL == "" then
		googleURL = "https://translate.google.com"
	elseif googleURL == "https://translate.google.com" then
		setVar(SONOS_SYS_SID, "GoogleTTSServerURL", "", device) -- restore default
	end
	local serverURL = getVar("OSXTTSServerURL", "", device, SONOS_SYS_SID, true)
	local maryURL = getVar("MaryTTSServerURL", "", device, SONOS_SYS_SID, true)
	local rvURL = getVar("ResponsiveVoiceTTSServerURL", "", device, SONOS_SYS_SID, true)
	if "" == rvURL then
		rvURL = "https://code.responsivevoice.org"
	elseif rvURL:match("^http:") or rvURL == "https://code.responsivevoice.org" then
		rvURL = "https://code.responsivevoice.org"
		setVar(SONOS_SYS_SID, "ResponsiveVoiceTTSServerURL", "", device)
	end
	local clientId = getVar("MicrosoftClientId", "", device, SONOS_SYS_SID, true)
	local clientSecret = getVar("MicrosoftClientSecret", "", device, SONOS_SYS_SID, true)
	local option = getVar("MicrosoftOption", "", device, SONOS_SYS_SID, true)
	-- NOTA BENE! TTSBaseURL must resolve to TTSBasePath in runtime! That is, whatever directory
	--            TTSBasePath points to must be the directory accessed via TTSBaseURL.
	TTSBaseURL = getVar("TTSBaseURL", "", device, SONOS_SYS_SID, true)
	if ttsrev < 19269 or not TTSBaseURL:match("%/$") then
		setVar(SONOS_SYS_SID, "TTSBaseURL", "", device)
		TTSBaseURL = ""
	end
	if "" == TTSBaseURL then
		if isOpenLuup then
			TTSBaseURL = string.format("http://%s:3480/", VERA_LOCAL_IP)
		elseif luup.short_version then
			-- 7.30+
			TTSBaseURL = string.format("http://%s/sonos/", VERA_LOCAL_IP)
		else
			TTSBaseURL = string.format("http://%s/port_3480/", VERA_LOCAL_IP)
		end
	end
	TTSBasePath = getVar("TTSBasePath", "", device, SONOS_SYS_SID, true)
	if ttsrev < 19269 or not TTSBasePath:match("%/$") then
		setVar(SONOS_SYS_SID, "TTSBasePath", "", device)
		TTSBasePath = ""
	end
	if "" == TTSBasePath then
		TTSBasePath = getInstallPath()
		if not isOpenLuup and luup.short_version then
			-- Real Vera 7.30+
			TTSBasePath = "/www/sonos/"
		end
	end
	setVar(SONOS_SYS_SID, "_ttsrev", 19269, device)

	tts.setup(lang, engine, googleURL, serverURL, maryURL, rvURL, clientId, clientSecret, option)

	local RV = tts.getEngine("RV")
	if RV then
		local rate = getVar("TTSRate", "", device, SONOS_SYS_SID, true)
		if "" == rate then
			rate = "0.5"
		elseif "0.5" == rate then
			setVar(SONOS_SYS_SID, "TTSRate", "", device) -- restore default
		end
		local pitch = getVar("TTSPitch", "", device, SONOS_SYS_SID, true)
		if "" == pitch then
			pitch = "0.5"
		elseif "0.5" == pitch then
			setVar(SONOS_SYS_SID, "TTSPitch", "", device) -- restore default
		end
		RV.pitch = pitch
		RV.rate = rate
	end

	TTSChime = nil
	local installPath = getInstallPath()
	if file_exists( installPath .. "Sonos_chime.wav" ) then
		if TTSBasePath ~= installPath then
			os.execute( "ln -sf " .. installPath .. "Sonos_chime.wav " .. TTSBasePath )
		end
		TTSChime = { URI=TTSBaseURL.."Sonos_chime.wav" }
		TTSChime.URIMetadata = TTS_METADATA:format( "TTS Chime", "http-get:*:audio/wav:*", TTSChime.URI )
		TTSChime.Duration = getVarNumeric( "TTSChimeDuration", 3, device, SONOS_SYS_SID )
		TTSChime.TempFile = nil -- flag no delete in endPlayback
	end
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

-- File copy. Why? So that symlinks are copied as actual file contents.
local function cp( fromPath, toPath )
	local ff = io.open( fromPath, "rb" )
	if not ff then return false end
	local tf = io.open( toPath, "wb" )
	if not tf then ff:close() return false end
	local nb = 0
	while true do
		local s = ff:read(2048)
		if not s then break end
		tf:write(s)
		nb = nb + #s
	end
	tf:close()
	ff:close()
	return nb
end

-- Fix the locations of the legacy icons. This can eventually go away. 7.30: Or can it? :(
local function fixLegacyIcons()
	if isOpenLuup then return end
	local basePath = getInstallPath()
	function moveIcon( p )
		if not file_exists( basePath .. p ) then
			-- File missing from basePath; try to locate it.
			if file_exists( basePath .. p .. ".lzo" ) then
				-- Decompress
				os.execute( "pluto-lzo d " .. basePath .. p..".lzo " .. basePath .. p )
			elseif file_exists( "/www/cmh/skins/default/icons/" .. p ) then
				-- cp instead of mv so Luup doesn't complain about missing plugin files
				cp( "/www/cmh/skins/default/icons/"..p, basePath .. p )
			elseif file_exists( "/www/cmh/skins/default/img/devices/device_states/" .. p ) then
				cp( "/www/cmh/skins/default/img/device/device_states/" .. p, basePath .. p )
			end
		elseif file_exists( basePath .. p .. ".lzo" ) then
			-- Both compressed and uncompressed exist.
			if file_dtm( basePath .. p .. ".lzo" ) > file_dtm( basePath .. p ) then
				-- Decompress newer file
				os.execute( "pluto-lzo d " .. basePath .. p ..".lzo " .. basePath .. p )
			end
		end
		if file_exists( basePath .. p ) then
			-- Apparently as of 7.30, this is new designated location.
			if not file_exists( "/www/cmh/skins/default/icons/"..p ) then
				os.execute( "ln -sf " .. basePath .. p .." /www/cmh/skins/default/icons/" )
			end
		end
	end
	moveIcon( "Sonos.png" )
	for k=0,150,25 do moveIcon( "Sonos_"..tostring(k)..".png" ) end
end

-- Set up custom icon for device. The icon is retrieved from the device
-- itself to a local copy, then a custom static JSON file is generated and
-- assigned to the device.
local function setDeviceIcon( device, icon, model, uuid )
	-- Set up local copy of icon from device and static JSON pointing to it
	-- (so icon works both locally and remote)
	local ICONREV = 19295
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
		os.execute( "curl -s -o " .. Q( installPath..iconFile ) .. " " .. Q( icon ) )
	end
	if installPath ~= iconPath then
		os.execute( "ln -sf " .. Q(installPath..iconFile) .. " " .. Q(iconPath) )
	end
	-- See if we've already created a custom static JSON for this UUID or model.
	local staticJSONFile
	if ( uuid or "") ~= "" then
		staticJSONFile = string.format( "D_Sonos1_%s.json", tostring( uuid ):lower():gsub( "[^a-z0-9_]", "_" ) )
		if file_exists_LZO( installPath .. staticJSONFile ) then
			L("Using device-specific UI %s", staticJSONFile )
		else
			staticJSONFile = nil
		end
	end
	if not staticJSONFile then
		staticJSONFile = string.format( "D_Sonos1_%s.json", tostring( model or "GENERIC" ):upper():gsub( "[^A-Z0-9_]", "_" ) )
	end
	if icorev < ICONREV or not file_exists_LZO( installPath .. staticJSONFile ) then
		-- Create model-specific version of static JSON
		L("Creating custom static JSON (device UI) in %1", staticJSONFile)
		local s,f = file_exists( installPath.."D_Sonos1.json", true )
		if not s then
			os.execute( 'pluto-lzo d ' .. Q(installPath .. 'D_Sonos1.json.lzo') .. ' /tmp/D_Sonos1.json.tmp' )
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
			local json = require "dkjson"
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
	D("handleRenderingChange(%1,%2)", uuid, event)
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
	if changed and Zones[uuid] then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), Zones[uuid])
	end
end

local function handleAVTransportChange(uuid, event)
	D("handleAVTransportChange(%1,%2)", uuid, event)
	local device = Zones[uuid] or 0
	local statusString, title, title2, artist, album, details, albumArt, desc
	local currentUri, currentUriMetaData, trackUri, trackUriMetaData, service, serviceId
	local changed = false
	local tschanged = false
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
				if token == "TransportState" then tschanged = vchanged end
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
			updateServicesMetaDataKeys(uuid, serviceId, desc)
		end

		if tschanged then
			-- Finally, after all other updates, check transport state if changed.
			checkTransportState(uuid)
		end
	end
	if changed and Zones[uuid] then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), Zones[uuid])
	end
end

local function handleContentDirectoryChange(device, uuid, id)
	D("handleContentDirectoryChange(%1,%2,%3)", device, uuid, id)
	local info
	local changed = false

	if (id:find("SQ:,") == 1) then
		-- Sonos playlists
		info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "SQ:", false, "dc:title", parseSavedQueues, BROWSE_TIMEOUT)
		changed = setData("SavedQueues", info, device, changed)
	elseif (id:find("R:0,") == 1) then
		-- Favorites radio stations
		info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "R:0/0", false, "dc:title", parseIdTitle, BROWSE_TIMEOUT)
		changed = setData("FavoritesRadios", info, device, changed)
	elseif (id:find("FV:2,") == 1) then
		-- Sonos favorites
		info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "FV:2", false, "dc:title", parseIdTitle, BROWSE_TIMEOUT)
		changed = setData("Favorites", info, device, changed)
	elseif (id:find("Q:0,") == 1) then
		-- Sonos queue
		if (fetchQueue) then
			info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "Q:0", false, "dc:title", parseQueue, BROWSE_TIMEOUT)
		else
			info = ""
		end
		changed = setData("Queue", info, device, changed)
	end
	if changed then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), device)
	end
end

-- N.B. called via call_delay from L_SonosUPnP
function processProxySubscriptions(info)
	D("Processing UPnP Event Proxy subscriptions: %1", info)
	upnp.processProxySubscriptions()
end

-- N.B. called via call_delay from L_SonosUPnP
function renewSubscriptions(data)
	D("renewSubscriptions(%1)", data)
	local device, uuid = data:match("(%d+):(.*)")
	device = tonumber(device)
	if device and uuid then
		if uuid ~= UUIDs[device] then
			D("Renewal ignored for uuid %1 (device %2/UUID mismatch, got %3)", uuid, device, UUIDs[device])
		elseif not upnp.subscribeToEvents(device, VERA_IP, EventSubscriptions[uuid], SONOS_ZONE_SID, uuid) then
			setup(device, true)
		end
	end
end

-- N.B. called via call_delay from L_SonosUPnP
function cancelProxySubscription(sid)
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

	luup.variable_set(SONOS_SYS_SID, "FetchQueue", enable, pluginDevice)
	if (enable == "1")
	then
		fetchQueue = true
	else
		fetchQueue = false
	end
	handleContentDirectoryChange(device, UUIDs[device], "Q:0,")
end

-- Check that the proxy is running.
function checkProxy( task, device )
	D("checkProxy(%1,%2)", tostring(task), device)
	local version = upnp.getProxyApiVersion()
	local proxy = version ~= nil and version
	if version then
		L("UPnP Event Proxy identified - API version %1", version)
	else
		W("UPnP Event Proxy plugin could not be contacted; polling for status will be used. This is inefficient; please consider installing the plugin from the marketplace.")
	end
	if not proxy then
		upnp.unuseProxy()
	end
	task:delay(300)
end

setup = function(zoneDevice, flag)
	D("setup(%1,%2)", zoneDevice, flag)
	local changed = false

	local uuid = luup.attr_get( "altid", zoneDevice ) or error("Invalid UUID on device "..zoneDevice) -- "shouldn't happen"
	D("setup() uuid %1", uuid)
	upnp.resetServices( uuid )
	if EventSubscriptions[uuid] then
		upnp.cancelProxySubscriptions(EventSubscriptions)
		EventSubscriptions[uuid] = nil
	end
	Zones[uuid] = nil
	UUIDs[zoneDevice] = nil
	dataTable[uuid] = nil

	local newIP = getIPFromUUID( uuid )
	local oldIP = luup.attr_get( "ip", zoneDevice )
	D("setup() new IP %1 old %2", newIP, oldIP)
	if (newIP or "") == "" then
		-- Zone not currently in zone info (may be offline); use last known
		newIP = oldIP
	elseif newIP ~= oldIP then
		-- Update last known
		luup.attr_set( "ip", newIP, zoneDevice )
	end
	if (newIP or "") == "" then
		setVar("SonosOnline", "0", zoneDevice, SONOS_ZONE_SID)
		setVar("CurrentStatus", "Offline", zoneDevice, UPNP_AVTRANSPORT_SID)
		setVar("ProxyUsed", "", zoneDevice, SONOS_ZONE_SID) -- plugin variable??? different per zone?
		E("No/invalid IP address for #%1", zoneDevice)
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
	if not status then
		setVar("SonosOnline", "0", zoneDevice, SONOS_ZONE_SID)
		setVar("CurrentStatus", "Offline", zoneDevice, UPNP_AVTRANSPORT_SID)
		setVar("ProxyUsed", "", zoneDevice, SONOS_ZONE_SID) -- ??? plugin variable? see above
		W("Zone %1 (#%2) appears to be offline. %3", (luup.devices[zoneDevice] or {}).description,
			zoneDevice, uuid)
		return false
	end

	uuid = values.UDN:match("uuid:(.+)") or ""
	UUIDs[zoneDevice] = uuid
	Zones[uuid] = zoneDevice
	dataTable[uuid] = {}

	local newOnline = deviceIsOnline(zoneDevice)

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
	changed = setData("SonosModel", string.format("%d", model), uuid, changed)

	L("Device #%1 at %2 is %3, %4 (%5) uuid %6",
		tostring( zoneDevice ),
		tostring( newIP ),
		tostring( modelName ),
		tostring( values.modelNumber ),
		model,
		tostring( uuid )
	)

	-- Use pcall so any issue setting up icon does not interfere with initialization and operation
	pcall( setDeviceIcon, zoneDevice, icon, values.modelNumber, uuid )

	if upnp.proxyVersionAtLeast(1) then
		EventSubscriptions[uuid] = deepCopy( EventSubscriptionsTemplate )
		upnp.subscribeToEvents(zoneDevice, VERA_IP, EventSubscriptions[uuid], SONOS_ZONE_SID, uuid)
		if DEBUG_MODE then
			for _,sub in ipairs(EventSubscriptions[uuid]) do
				D("%1 event service %2 sid %3 expiry %4", uuid, sub.service, sub.id, sub.expiry)
			end
		end

		setVar(SONOS_SYS_SID, "ProxyUsed", "proxy is in use", zoneDevice)
		BROWSE_TIMEOUT = 30
	else
		setVar(SONOS_SYS_SID, "ProxyUsed", "proxy is not in use", zoneDevice)
		BROWSE_TIMEOUT = 5
	end

	if not sonosServices then
		sonosServices = getAvailableServices(uuid)
	end
	metaDataKeys[uuid] = loadServicesMetaDataKeys(zoneDevice)

	-- Sonos playlists
	local info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "SQ:", false,
		"dc:title", parseSavedQueues, BROWSE_TIMEOUT)
	changed = setData("SavedQueues", info, uuid, changed)

	-- Favorites radio stations
	info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "R:0/0", false,
		"dc:title", parseIdTitle, BROWSE_TIMEOUT)
	changed = setData("FavoritesRadios", info, uuid, changed)

	-- Sonos favorites
	info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "FV:2", false,
		"dc:title", parseIdTitle, BROWSE_TIMEOUT)
	changed = setData("Favorites", info, uuid, changed)

	if changed then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), zoneDevice)
	end

	local rate = getCheckStateRate(zoneDevice)
	if rate > 0 then
		local t = scheduler.getTask("checkState"..zoneDevice) or
			scheduler.Task:new("checkState"..zoneDevice, zoneDevice, checkDeviceState, { zoneDevice } )
		t:delay( rate, { replace=true } )
	end

	refreshNow( uuid, true, true ) -- direct call for inline

	return true
end

local function zoneRunOnce( dev )
	local s = getVarNumeric( "ConfigVersion", 0, dev, SONOS_SYS_SID ) -- yes, SYS
	if s == 0 then
		-- New zone device
		initVar( "SonosID", "", dev, SONOS_ZONE_SID )
		initVar( "SonosOnline", "0", dev, SONOS_ZONE_SID )
		initVar( "PollDelays", "15,60", dev, SONOS_ZONE_SID )
	end
	setVar( SONOS_SYS_SID, "ConfigVersion", 0 --[[ _CONFIGVERSION --]], dev )
end

local function systemRunOnce( pdev )
	local s = getVarNumeric( "ConfigVersion", 0, pdev, SONOS_SYS_SID )
	if s == 0 then
		-- First run
		initVar( "DebugLogs", 0, pdev, SONOS_SYS_SID )
	end

	setVar( SONOS_SYS_SID, "ConfigVersion", 0 --[[ _CONFIGVERSION --]], pdev )
end

local function startZone( zoneDevice )
	L("Starting %1 (#%2)", luup.devices[zoneDevice].description, zoneDevice)

	zoneRunOnce( zoneDevice )

	setup( zoneDevice, true )

	return true
end

local function runMasterTick( task )
	D("runMasterTick(%1)", task)
	-- At the moment, nothing to do, so don't reschedule, just go away.
	task:close()
end

-- Complete startup tasks. Hopefully everything is initialized by now.
local function deferredStartup(device)
	D("deferredStartup(%1)", device)
	device = tonumber(device)

	-- Allow configured no-proxy operation
	if getVarNumeric( "UseProxy", 1, device, SONOS_SYS_SID, true ) == 0 then
		upnp.unuseProxy()
	else
		scheduler.Task:new("checkProxy", device, checkProxy, { device }):delay(300)
	end

	-- Start zones
	UUIDs = {}
	Zones = {}
	local reload = false
	local count, started = 0, 0
	local children = {}
	for k,v in pairs( luup.devices ) do
		if v.device_type == SONOS_ZONE_DEVICE_TYPE then
			D("deferredStartup() found child %1 parent %2", k, v.device_num_parent)
			if v.device_num_parent == 0 then
				-- Old-style standalone; convert to child
				W("Adopting standalone (old) Sonos device by new parent %1", device)
				luup.attr_set( "impl_file", "", k )
				luup.attr_set( "id_parent", device, k )
				luup.attr_set( "altid", getVar( "SonosID", tostring(k), k, SONOS_ZONE_SID ), k )
				luup.set_failure( 1, k )
				reload = true
			elseif v.device_num_parent == device then
				children[k] = v
				count = count + 1
				local status,success = pcall( startZone, k )
				if status and success then
					luup.set_failure( 0, k )
					started = started + 1
				else
					luup.set_failure( 1, k )
				end
			end
		end
	end
	L("Started %1 children of %2", started, count)
	-- Disable old plugin implementation if present.
	local ipath = getInstallPath()
	if file_exists( ipath .. "I_Sonos1.xml.lzo" ) or file_exists( ipath .. "I_Sonos1.xml.lzo" ) then
		W("Removing old Sonos plugin implementations files (for standalone devices, no longer used)")
		os.execute("rm -f -- " .. ipath .. "I_Sonos1.xml.lzo " .. ipath .. "I_Sonos1.xml")
		os.execute("rm -f -- " .. ipath .. "L_Sonos1.lua.lzo " .. ipath .. "L_Sonos1.lua")
	end
	-- And reload if devices were upgraded.
	if reload then
		setVar( SONOS_SYS_SID, "Message", "Upgrading devices... please wait", pluginDevice )
		W("Converted old standalone devices to children; reloading Luup")
		luup.reload()
		return false, "Reload required", MSG_CLASS
	end

	-- If there are no children, launch discovery and see if we can find some.
	-- Otherwise, check the zone topology to see if there are zones we don't have.
	if count == 0 then
		L"No children; launching discovery to see who I can find."
		luup.call_action( SONOS_SYS_SID, "StartSonosDiscovery", {}, device )
	elseif zoneInfo and getVarNumeric( "StartupInventory", 1, device, SONOS_SYS_SID ) ~= 0 then
		D("deferredStartup() taking inventory")
		local newZones = {}
		for uuid in pairs( zoneInfo.zones ) do
			if not findDeviceByUUID( uuid ) then
				newZones[uuid] = getIPFromUUID( uuid ) or ""
			end
		end
		if next( newZones ) then
			setVar( SONOS_SYS_SID, "Message", "New device(s) found... please wait", pluginDevice )
			D("deferredStartup() rebuilding family")
			local ptr = luup.chdev.start( device )
			for k,v in pairs( children ) do
				if v.device_num_parent == device then
					local df = luup.attr_get('device_file', k)
					D("deferredStartup() appending existing child dev #%1 %2 uuid %3 device_file %4", k, v.description, v.id, df)
					luup.chdev.append( device, ptr, v.id, v.description, "", df, "", "", false )
				end
			end
			for uuid,ip in pairs( newZones ) do
				D("deferredStartup() appending new zone %1 ip %2", uuid, ip)
				local cv = {
					string.format( ",ip=%s", ip ),
					string.format( "%s,SonosID=%s", SONOS_ZONE_SID, uuid )
				}
				local name = zoneInfo.zones[uuid].ZoneName or uuid:gsub("RINCON_", "")
				luup.chdev.append( device, ptr, uuid, name, "", "D_Sonos1.xml", "",
					table.concat( cv, "\n" ), false )
			end
			luup.chdev.sync( device, ptr )
		end
	end

	D("deferredStartup() done. We're up and running!")
	setVar( SONOS_SYS_SID, "Message", string.format("Running %d zones", count), device )

	-- Start a new master task
	local t = scheduler.Task:new( "master", device, runMasterTick, { device } )
	t:delay( 60 )
end

local function waitForProxy( task, device, tries )
	D("waitForProxy(%1,%2,%3)", tostring(task), device, tries)
	tries = (tries or 0) + 1
	if getVarNumeric( "UseProxy", 1, device, SONOS_SYS_SID ) == 0
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

function startup( lul_device )
	L("Starting version %1 device #%2 (%3)", PLUGIN_VERSION, lul_device,
		luup.devices[lul_device].description)

	isOpenLuup = luup.openLuup ~= nil
	pluginDevice = lul_device

	local debugLogs = getVarNumeric("DebugLogs", 0, lul_device, SONOS_SYS_SID)
	setDebugLogs(debugLogs)

	systemRunOnce( lul_device )

	setVar( SONOS_SYS_SID, "PluginVersion", PLUGIN_VERSION, lul_device )
	setVar( SONOS_SYS_SID, "Message", "Starting...", lul_device )

	scheduler = TaskManager( 'sonosTick' )

	if not isOpenLuup and luup.short_version then
		-- Real Vera 7.30+
		os.execute("mkdir -p /www/sonos/")
	end
	pcall( fixLegacyIcons )

	D("startup() UPnP module version is %1", upnp.VERSION)
	if ( upnp.VERSION or 0 ) < MIN_UPNP_VERSION then
		E"The L_SonosUPNP module installed is not compatible with this version of the plugin core."
		return false, "Invalid installation", MSG_CLASS
	end
	if not tts then
		L("TTS module is not installed (it's optional)")
	else
		D("TTS module version is %1", tts.VERSION)
		if ( tts.VERSION or 0 ) < MIN_TTS_VERSION then
			W("The L_SonosTTS module installed may not be compatible with this version of the plugin core.")
		end
	end

	local enabled = initVar( "Enabled", "1", lul_device, SONOS_SYS_SID )
	if "0" == enabled then
		W("%1 (#%2) disabled by configuration; startup aborting.", luup.devices[lul_device].description,
			lul_device)
		-- ??? offline children?
		setVar( SONOS_SYS_SID, "Message", "Disabled", lul_device )
		return true, "Disabled", MSG_CLASS
	end

	setVar( SONOS_SYS_SID, "DiscoveryMessage", "", lul_device )

	local routerIp = getVar("RouterIp", "", lul_device, SONOS_SYS_SID, true)
	local routerPort = getVar("RouterPort", "", lul_device, SONOS_SYS_SID, true)

	initVar("CheckStateRate", "", lul_device, SONOS_SYS_SID)

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
	if VERA_LOCAL_IP == "" then
		local stdout = io.popen("GetNetworkState.sh ip_wan")
		VERA_LOCAL_IP = stdout:read("*a")
		stdout:close()
	end
	D("startup(): controller IP address is %1", VERA_LOCAL_IP)
	if VERA_LOCAL_IP == "" then
		E("Unable to establish local IP address of Vera/openLuup system. Please set 'LocalIP'")
		luup.set_failure( 1, lul_device )
		return false, "Unable to establish local IP -- see log", PLUGIN_NAME
	end

	if routerIp == "" then
		VERA_IP = VERA_LOCAL_IP
	else
		VERA_IP = routerIp
	end
	if routerPort ~= "" then
		VERA_WEB_PORT = tonumber(routerPort)
	end

	ip, playbackCxt, sayPlayback, UUIDs, metaDataKeys, dataTable = upnp.initialize(L, W, E)

	if tts then
		tts.initialize(L, W, E)
	end
	setupTTSSettings(lul_device)

	port = 1400

	luup.variable_set(SONOS_SYS_SID, "DiscoveryPatchInstalled",
		upnp.isDiscoveryPatchInstalled(VERA_LOCAL_IP) and "1" or "0", lul_device)

	-- Deferred startup, on the master tick task.
	local t = scheduler.Task:new( "master", lul_device, waitForProxy, { lul_device } )
	t:delay( 3 )

	luup.set_failure( 0, lul_device )
	return true, "", MSG_CLASS
end

--[[

	TTS Support Functions

--]]

endSayAlert = false-- Forward declaration, non-local

local function sayOrAlert(device, parameters, saveAndRestore)
	local instanceId = defaultValue(parameters, "InstanceID", "0")
	-- local channel = defaultValue(parameters, "Channel", "Master")
	local volume = defaultValue(parameters, "Volume", nil)
	local devices = defaultValue(parameters, "GroupDevices", "")
	local zones = defaultValue(parameters, "GroupZones", "")
	local uri = defaultValue(parameters, "URI", nil)
	local duration = defaultValue(parameters, "Duration", "0")
	local sameVolume = false
	if (parameters.SameVolumeForAll == "true"
		or parameters.SameVolumeForAll == "TRUE"
		or parameters.SameVolumeForAll == "1") then
		sameVolume = true
	end

	-- If empty URI is passed, abandon all TTS/alerts
	if (uri or "") == "" then
		if sayPlayback[device] then
			-- Leave queue with currently playing element
			while sayQueue[device] and #sayQueue[device] > 1 do
				table.remove( sayQueue[device] )
			end
			-- Rush the end task
			local task = scheduler.getTask( "endSayAlert"..device)
			if task then
				task:delay( 0, { replace=true } )
			end
		end
		return
	end

	local targets = {}
	local newGroup = true
	local localUUID = UUIDs[device]

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
			elseif not UUIDs[nid] then
				W("Say/Alert action GroupDevices device %1 not a known Sonos device (ignored)", id)
			else
				uuid = UUIDs[nid]
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
			-- ??? FIXME -- here we need to find coordinator, and add it and all group members
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

		-- Now, find any targets that happen to be coordinators of groups. All members are affected
		-- by removing/changing the coordinator when the temporary alert group is created.
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
		D("sayOrAlert() final affected list is %1", affected)
		sayPlayback[device] = savePlaybackContexts( device, keys( affected ) )
		sayPlayback[device].newGroup = newGroup -- signal to endSay

		-- Pause all affected zones. If we need a temporary group, remove all non-coordinators;
		-- this leaves all affected players as standalone. playURI will go the grouping.
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
		end
	end

	playURI(localUUID, instanceId, uri, "1", volume, newGroup and keys(targets) or nil, sameVolume, nil, newGroup, true)

	if saveAndRestore then
		if (tonumber(duration) or 0) <= 0 then duration = 30 end
		D("sayOrAlert() delaying for duration %1", duration)
		local t = scheduler.getTask("endSayAlert"..device) or scheduler.Task:new("endSayAlert"..device, device, endSayAlert, { device })
		t:delay( duration, { replace=true } )
	end

	updateNow( device )
end

local function queueAlert(device, settings)
	D("queueAlert(%1,%2)", device, settings)
	sayQueue[device] = sayQueue[device] or {}
	local first = #sayQueue[device] == 0
	table.insert(sayQueue[device], settings)
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
		if settings.TempFile then
			-- Remove temp file
			os.execute(string.format("rm -f -- %s", Q(settings.TempFile)))
		end
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
				-- Temporary group was used; reset group structure.
				-- First remove all to-be-restored devices from their current groups.
				D("endSayAlert() restoring group structure after temporary group")
				for uuid in pairs( playCxt.context or {} ) do
					D("endSayAlert() clearing group for %1", uuid)
					local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
					if AVTransport ~= nil then
						AVTransport.Stop({InstanceID="0"})
						AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID="0"})
					end
				end

				D("endSayAlert() restoring group structure")
				for uuid,cxt in pairs( playCxt.context or {} ) do
					-- D("endSayAlert() affected %1 context ", uuid, cxt)
					if cxt.GroupCoordinator ~= uuid then
						D("endSayAlert() restoring member %1 to %2", uuid, cxt.GroupCoordinator)
						-- Add this uuid to its prior GroupCoordinator
						if controlAnotherZone( uuid, UUIDs[device] ) then
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
	local json = require "dkjson"
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

local function makeTTSAlert( device, settings )
	local text = settings.Text or "42"
	local engobj = tts.getEngine( settings.Engine )
	cacheTTS = not file_exists( TTSBasePath .. "no-tts-cache" )
	if cacheTTS then
		local fmeta = loadTTSCache( settings.Engine, settings.Language, hash(text) )
		if fmeta.strings[text] then
			settings.Duration = fmeta.strings[text].duration
			settings.URI = TTSBaseURL .. fmeta.strings[text].url
			settings.URIMetadata = TTS_METADATA:format(engobj.title, engobj.protocol,
				settings.URI or "")
			settings.TempFile = nil -- flag no delete in endPlayback
			L("(TTS) Speaking phrase from cache: %1", settings.URI)
			return settings
		end
	end
	if engobj then
		-- Convert text to speech using specified engine
		local file = string.format( "Say.%s.%s", tostring(device), engobj.fileType or "mp3" )
		local destFile = TTSBasePath .. file
		settings.Duration = tts.ConvertTTS(text, destFile, settings.Language, settings.Engine, {})
		if (settings.Duration or 0) == 0 then
			W("(tts) Engine %1 produced no audio", engobj.title)
			return
		end
		settings.URI = TTSBaseURL .. file
		settings.TempFile = destFile
		settings.URIMetadata = TTS_METADATA:format(engobj.title, engobj.protocol,
			settings.URI)
		L("(TTS) Engine %1 created %2", engobj.title, settings.URI)
		if cacheTTS then
			-- Save in cache
			local fmeta, curl = loadTTSCache( settings.Engine, settings.Language, hash(text) )
			local cpath = TTSBasePath .. curl
			local ft = file:match("[^/]+$"):match("%.[^%.]+$") or ""
			os.execute("mkdir -p " .. Q(cpath))
			while true do
				local zf = io.open( cpath .. fmeta.nextfile .. ft, "r" )
				if not zf then break end
				zf:close()
				fmeta.nextfile = fmeta.nextfile + 1
			end
			if os.execute( "cp -f -- " .. Q( destFile ) .. " " .. Q( cpath .. fmeta.nextfile .. ft ) ) ~= 0 then
				W("(TTS) Cache failed to copy %1 to %2", destFile, cpath..fmeta.nextfile..ft)
			else
				fmeta.strings[text] = { duration=settings.Duration, url=curl .. fmeta.nextfile .. ft, created=os.time() }
				fm = io.open( cpath .. "ttsmeta.json", "w" )
				if fm then
					local json = require "dkjson"
					fmeta.nextfile = fmeta.nextfile + 1
					fm:write(json.encode(fmeta))
					fm:close()
					D("makeTTSAlert() cached %1 as %2", destFile, fmeta.strings[text].url)
				else
					W("(TTS) Can't write cache meta in %1", cpath)
				end
			end
		end
	else
		W("No TTS engine implementation for %1", settings.Engine)
		return nil
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
		return
	end
	if ( tts.VERSION or 0 ) < MIN_TTS_VERSION then
		W"The L_SonosTTS module installed may not be compatible with this version of the plugin core."
	end
	if ( luup.attr_get( 'UnsafeLua', 0 ) or "0" ) ~= "1" and not isOpenLuup then
		W"The TTS module requires that 'Enable Unsafe Lua' (under 'Users & Account Info > Security') be enabled in your controller settings."
		return
	end
	-- ??? Request handler doesn't unescape?
	lul_settings.Text = url.unescape( lul_settings.Text )
	-- Play as alert.
	local alert_settings = makeTTSAlert( lul_device, lul_settings )
	if alert_settings then
		if TTSChime and lul_settings.Chime ~= "0" and #(sayQueue[lul_device] or {}) == 0 then
			TTSChime.GroupDevices = lul_settings.GroupDevices
			TTSChime.GroupZones = lul_settings.GroupZones
			TTSChime.Volume = lul_settings.Volume
			queueAlert( lul_device, TTSChime )

			-- Override alert settings to use same zone group as chime
			alert_settings.GroupDevices = nil
			alert_settings.GroupZones = "CURRENT"
		end
		queueAlert( lul_device, alert_settings )
	end
end

function actionSonosSetupTTS( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_SYS_DEVICE_TYPE)
	luup.variable_set(SONOS_SYS_SID, "DefaultLanguageTTS"				, lul_settings.DefaultLanguage or "", lul_device)
	luup.variable_set(SONOS_SYS_SID, "DefaultEngineTTS"					, lul_settings.DefaultEngine or "", lul_device)
	luup.variable_set(SONOS_SYS_SID, "OSXTTSServerURL"					, url.unescape(lul_settings.OSXTTSServerURL				or ""), lul_device)
	luup.variable_set(SONOS_SYS_SID, "GoogleTTSServerURL"				, url.unescape(lul_settings.GoogleTTSServerURL			or ""), lul_device)
	luup.variable_set(SONOS_SYS_SID, "MaryTTSServerURL"					, url.unescape(lul_settings.MaryTTSServerURL			or ""), lul_device)
	luup.variable_set(SONOS_SYS_SID, "MicrosoftClientId"				, url.unescape(lul_settings.MicrosoftClientId			or ""), lul_device)
	luup.variable_set(SONOS_SYS_SID, "MicrosoftClientSecret"			, url.unescape(lul_settings.MicrosoftClientSecret		or ""), lul_device)
	luup.variable_set(SONOS_SYS_SID, "MicrosoftOption"					, url.unescape(lul_settings.MicrosoftOption				or ""), lul_device)
	luup.variable_set(SONOS_SYS_SID, "ResponsiveVoiceTTSServerURL"		, url.unescape(lul_settings.ResponsiveVoiceTTSServerURL	or ""), lul_device)
	luup.variable_set(SONOS_SYS_SID, "TTSRate"							, url.unescape(lul_settings.Rate						or ""), lul_device)
	luup.variable_set(SONOS_SYS_SID, "TTSPitch"							, url.unescape(lul_settings.Pitch						or ""), lul_device)
	setupTTSSettings(lul_device)
	os.execute( "rm -rf -- " .. Q(TTSBasePath .. "ttscache") )
end

function actionSonosResetTTS( lul_device )
	assert(luup.devices[lul_device].device_type == SONOS_SYS_DEVICE_TYPE)
	luup.variable_set(SONOS_SYS_SID, "DefaultLanguageTTS"			, "", lul_device)
	luup.variable_set(SONOS_SYS_SID, "DefaultEngineTTS"				, "", lul_device)
	luup.variable_set(SONOS_SYS_SID, "OSXTTSServerURL"				, "", lul_device)
	luup.variable_set(SONOS_SYS_SID, "GoogleTTSServerURL"			, "", lul_device)
	luup.variable_set(SONOS_SYS_SID, "MaryTTSServerURL"				, "", lul_device)
	luup.variable_set(SONOS_SYS_SID, "MicrosoftClientId"			, "", lul_device)
	luup.variable_set(SONOS_SYS_SID, "MicrosoftClientSecret"		, "", lul_device)
	luup.variable_set(SONOS_SYS_SID, "MicrosoftOption"				, "", lul_device)
	luup.variable_set(SONOS_SYS_SID, "ResponsiveVoiceTTSServerURL"	, "", lul_device)
	luup.variable_set(SONOS_SYS_SID, "TTSRate"						, "", lul_device)
	luup.variable_set(SONOS_SYS_SID, "TTSPitch"						, "", lul_device)
	luup.variable_set(SONOS_SYS_SID, "TTSBasePath"					, "", lul_device)
	luup.variable_set(SONOS_SYS_SID, "TTSBaseURL"					, "", lul_device)
	setupTTSSettings(lul_device)
end

function actionSonosSetURIToPlay( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local uri = defaultValue(lul_settings, "URIToPlay", "")

	playURI(UUIDs[lul_device], instanceId, uri, nil, nil, nil, false, nil, false, true)

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
end

function actionSonosPlayURI( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local uri = defaultValue(lul_settings, "URIToPlay", "")
	local volume = defaultValue(lul_settings, "Volume", nil)
	local speed = defaultValue(lul_settings, "Speed", "1")

	playURI(UUIDs[lul_device], instanceId, uri, speed, volume, nil, false, nil, false, true)

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
end

function actionSonosEnqueueURI( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local uri = defaultValue(lul_settings, "URIToEnqueue", "")
	local enqueueMode = defaultValue(lul_settings, "EnqueueMode", "ENQUEUE_AND_PLAY")

	playURI(UUIDs[lul_device], instanceId, uri, "1", nil, nil, false, enqueueMode, false, true)

	updateNow( lul_device )
end

function actionSonosAlert( lul_device, lul_settings )
	D("actionSonosAlert(%1,%2)", lul_device, lul_settings)
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	L("Alert action on device %1 URI %2 duration %3", lul_device, lul_settings.URI, lul_settings.Duration)
	queueAlert(lul_device, lul_settings)
end

function actionSonosPauseAll( lul_device, lul_settings ) -- luacheck: ignore 212
	pauseAll(lul_device)
end

function actionSonosJoinGroup( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local zone = defaultValue(lul_settings, "Zone", "")
	joinGroup(UUIDs[lul_device], zone)
end

function actionSonoLeaveGroup( lul_device, lul_settings ) -- luacheck: ignore 212
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	leaveGroup(UUIDs[lul_device])
end

function actionSonosUpdateGroupMembers( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local zones = url.unescape(defaultValue(lul_settings, "Zones", ""))
	updateGroupMembers(UUIDs[lul_device], zones)
end

function actionSonosSavePlaybackContext( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_SYS_DEVICE_TYPE)
	local devices = defaultValue(lul_settings, "GroupDevices", "")
	local zones = defaultValue(lul_settings, "GroupZones", "")

	local targets = { UUIDs[lul_device] }

	if (zones:upper() == "ALL") then
		_, targets = getAllUUIDs()
	else
		for id in devices:gmatch("[^,]+") do
			local nid = tonumber(id)
			local uuid = nil
			if not ( nid and UUIDs[nid] ) then
				W("SavePlaybackContext action GroupDevices element %1 invalid or unknown device", id)
			else
				uuid = UUIDs[nid]
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
	setVariableValue(SONOS_SYS_SID, "DiscoveryMessage", "Scanning...", lul_device)
	local xml, devices = upnp.scanUPnPDevices("urn:schemas-upnp-org:device:ZonePlayer:1", { "modelName", "friendlyName", "roomName" })
	setVariableValue(SONOS_SYS_SID, "DiscoveryResult", xml, lul_device)
	if not devices then
		setVariableValue(SONOS_SYS_SID, "DiscoveryMessage", "Aborted. See log for errors.", lul_device)
	else
		D("actionSonosStartDiscovery() discovered %1", devices)
		local children = {}
		for n,v in pairs(luup.devices) do
			if v.device_type == SONOS_ZONE_DEVICE_TYPE and v.device_num_parent == lul_device then
				children[v.id] = n
			end
		end
		local newChildren = {}
		for _,zone in ipairs(devices) do
			if zone.udn then
				local zoneDev = children[zone.udn]
				if not zoneDev then
					-- New zone
					D("actionSonosStartDiscovery() new zone %1", zone.udn)
					table.insert( newChildren, zone )
				elseif zone.ip ~= luup.attr_get( "ip", zoneDev ) then
					-- Existing zone, IP changed
					L("Discovery detected IP address change for %1 (#%3 %4) to %2",
						zone.udn, zone.ip, zoneDev, luup.devices[zoneDev].description)
					luup.attr_set( "ip", zone.ip, zoneDev )
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
				string.format("Found %d new zones; creating devices...", #newChildren), lul_device)
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
				table.insert( cv, string.format( ",ip=%s", zone.ip ) )
				table.insert( cv, string.format( "%s,SonosID=%s", SONOS_ZONE_SID, zone.udn ) )
				table.insert( cv, string.format( "%s,Port=%s", SONOS_ZONE_SID, zone.port or 1400 ) )
				local name = zone.udn:upper():gsub("RINCON_","")
				luup.chdev.append( lul_device, ptr, zone.udn, name, "", "D_Sonos1.xml", "",
					table.concat( cv, "\n" ), false )
			end
			setVariableValue(SONOS_SYS_SID, "DiscoveryMessage",
				string.format("Completed. %d new zones added.", #newChildren), lul_device)
			L("Discovery complete. %d new zones added. Requesting Luup reload.", #newChildren)
			luup.chdev.sync( lul_device, ptr )
		else
			setVariableValue(SONOS_SYS_SID, "DiscoveryMessage", "Completed. No new devices found.", lul_device)
			L"Discovery complete. No new zones found."
		end
	end
	return 4,0
end

function actionSonosSelectDevice( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local newDescrURL = url.unescape( lul_settings.URL or "" )
	local newIP, newPort = newDescrURL:match("http://([%d%.]-):(%d+)/.-")
	if (newIP ~= nil and newPort ~= nil) then
		luup.attr_set("ip", newIP, lul_device)
		luup.attr_set("mac", "", lul_device)
		setup(lul_device, false)
	end
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
			luup.attr_set("ip", newIP, lul_device)
			luup.attr_set("mac", "", lul_device)
			setup(lul_device, false)
		end
	end
	return 4,0
end

function actionSonosSetCheckStateRate( lul_device, lul_settings )
	setCheckStateRate(lul_device, lul_settings.rate)
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
end

function actionSonosNotifyRenderingChange( lul_device, lul_settings )
	local uuid = UUIDs[lul_device]
	D("actionSonosNotifyRenderingChange(%1,%2)", lul_device, lul_settings)
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
	local uuid = UUIDs[lul_device]
	D("actionSonosNotifyAVTransportChange(%1,%2)", lul_device, lul_settings)
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
	local uuid = UUIDs[lul_device]
	D("actionSonosNotifyMusicServicesChange(%1,%2)", lul_device, lul_settings)
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	assert( uuid ~= nil )
	assert( EventSubscriptions[uuid] ~= nil )
	if (upnp.isValidNotification("NotifyMusicServicesChange", lul_settings.sid, EventSubscriptions[uuid])) then
		-- log("NotifyMusicServicesChange for device " .. lul_device .. " SID " .. lul_settings.sid .. " with value " .. (lul_settings.LastChange or "nil"))
		sonosServices = getAvailableServices(uuid)
		metaDataKeys[uuid] = loadServicesMetaDataKeys(lul_device)
		return 4,0
	end
	return 2,0
end

function actionSonosNotifyZoneGroupTopologyChange( lul_device, lul_settings )
	local uuid = UUIDs[lul_device]
	D("actionSonosNotifyZoneGroupTopologyChange(%1,%2)", lul_device, lul_settings)
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	assert( uuid ~= nil )
	assert( EventSubscriptions[uuid] ~= nil )
	if (upnp.isValidNotification("NotifyZoneGroupTopologyChange", lul_settings.sid, EventSubscriptions[uuid])) then
		groupsState = lul_settings.ZoneGroupState or "<ZoneGroupState/>"

		local changed = setData("ZoneGroupState", groupsState, uuid, false)
		if changed or not zoneInfo then
			updateZoneInfo( uuid )
		end

		local members, coordinator = getGroupInfos( uuid )
		changed = setData("ZonePlayerUUIDsInGroup", members, uuid, changed)
		changed = setData("GroupCoordinator", coordinator, uuid, changed)

		if changed then
			setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), lul_device)
		end
		return 4,0
	end
	return 2,0
end

function actionSonosNotifyContentDirectoryChange( lul_device, lul_settings )
	local uuid = UUIDs[lul_device]
	D("actionSonosNotifyContentDirectoryChange(%1,%2)", lul_device, lul_settings)
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
	local uuid = UUIDs[lul_device]
	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return false
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
end

function actionVolumeUp( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	-- Volume up
	local uuid = UUIDs[lul_device]
	if tostring(dataTable[uuid].OutputFixed or 0) ~= "0" then
		W("Can't change volume on fixed output zone %1 (#%2)", luup.devices[lul_device].description, lul_device)
		return
	end

	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local channel = defaultValue(lul_settings, "Channel", "Master")

	Rendering.SetRelativeVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "Adjustment=3"}})

	refreshVolumeNow(uuid)
end

function actionVolumeDown( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	-- Volume down
	local uuid = UUIDs[lul_device]
	if tostring(dataTable[uuid].OutputFixed or 0) ~= "0" then
		W("Can't change volume on fixed output zone %1 (#%2)", luup.devices[lul_device].description, lul_device)
		return
	end

	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return false
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local channel = defaultValue(lul_settings, "Channel", "Master")

	Rendering.SetRelativeVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "Adjustment=-3"}})

	refreshVolumeNow(uuid)
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:micasaverde-com:serviceId:MediaNavigation1

--]]

function actionMediaNavigationSkipDown( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Next({InstanceID=instanceId})

	-- Force a refresh when current service is Pandora due to a bug (missing notification)
	local force = false
	local currentUri = dataTable[uuid].AVTransportURI
	if (currentUri ~= nil and currentUri:find("pndrradio:") == 1) then
		force = true
	end

	updateNow( device )
end

function actionMediaNavigationSkipUp( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Previous({InstanceID=instanceId})

	updateNow( device )
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:upnp-org:serviceId:AVTransport

--]]

function actionAVTransportPlayMedia( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local speed = defaultValue(lul_settings, "Speed", "1")

	AVTransport.Play(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"Speed=" ..speed}})

	-- Force a refresh when current service is Pandora due to a bug (missing notification)
	local force = false
	local currentUri = dataTable[uuid].AVTransportURI
	if (currentUri ~= nil and currentUri:find("pndrradio:") == 1) then
		force = true
	end

	updateNow( device )
end

function actionAVTransportSeek( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local unit = defaultValue(lul_settings, "Unit", "")
	local target = defaultValue(lul_settings, "Target", "")

	AVTransport.Seek(
		{OrderedArgs={"InstanceID=" ..instanceId,
					"Unit=" .. unit,
					"Target=" .. target}})
end

function actionAVTransportPause( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Pause({InstanceID=instanceId})

	-- Force a refresh when current service is Pandora due to a bug (missing notification)
	local force = false
	local currentUri = dataTable[uuid].AVTransportURI
	if (currentUri ~= nil and currentUri:find("pndrradio:") == 1) then
		force = true
	end

	updateNow( device )
end

function actionAVTransportStop( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Stop({InstanceID=instanceId})

	updateNow( device )
end

function actionAVTransportNext( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Next({InstanceID=instanceId})

	updateNow( device )
end

function actionAVTransportPrevious( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Previous({InstanceID=instanceId})

	updateNow( device )
end

function actionAVTransportNextSection( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.NextSection({InstanceID=instanceId})

	updateNow( device )
end

function actionAVTransportPreviousSection( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.PreviousSection({InstanceID=instanceId})

	updateNow( device )
end

function actionAVTransportNextProgrammedRadioTracks( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.NextProgrammedRadioTracks({InstanceID=instanceId})

	updateNow( device )
end

function actionAVTransportGetPositionInfo( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	local _, tmp = AVTransport.GetPositionInfo({InstanceID=instanceId})
	setData("RelativeTimePosition", upnp.extractElement("RelTime", tmp, "NOT_IMPLEMENTED"), device, false)
end

function actionAVTransportSetPlayMode( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local newPlayMode = defaultValue(lul_settings, "NewPlayMode", "NORMAL")

	-- NORMAL, SHUFFLE, SHUFFLE_NOREPEAT, REPEAT_ONE, REPEAT_ALL, RANDOM, DIRECT_1, INTRO
	AVTransport.SetPlayMode(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"NewPlayMode=" .. newPlayMode}})
end

function actionAVTransportSetURI( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local currentURI = defaultValue(lul_settings, "CurrentURI", "")
	local currentURIMetaData = defaultValue(lul_settings, "CurrentURIMetaData", "")

	AVTransport.SetAVTransportURI(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"CurrentURI=" .. currentURI,
						"CurrentURIMetaData=" .. currentURIMetaData}})

	updateNow( lul_device )
end

function actionAVTransportSetNextURI( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local nextURI = defaultValue(lul_settings, "NextURI", "")
	local nextURIMetaData = defaultValue(lul_settings, "NextURIMetaData", "")

	AVTransport.SetNextAVTransportURI(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"NextURI=" .. nextURI,
						"NextURIMetaData=" .. nextURIMetaData}})
end

function actionAVTransportAddMultipleURIs( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
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
end

function actionAVTransportAddURI( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
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
end

function actionAVTransportCreateSavedQueue( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
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
end

function actionAVTransportAddURItoSaved( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
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
end

function actionAVTransportReorderQueue( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.ReorderTracksInQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"StartingIndex=" .. lul_settings.StartingIndex,
						"NumberOfTracks=" .. lul_settings.NumberOfTracks,
						"InsertBefore=" .. lul_settings.InsertBefore,
						"UpdateID=" .. lul_settings.UpdateID}})
end

function actionAVTransportReorderSaved( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.ReorderTracksInSavedQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"ObjectID=" .. lul_settings.ObjectID,
						"UpdateID=" .. lul_settings.UpdateID,
						"TrackList=" .. lul_settings.TrackList,
						"NewPositionList=" .. lul_settings.NewPositionList}})
end

function actionAVTransportRemoveTrackFromQueue( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.RemoveTrackFromQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"ObjectID=" .. lul_settings.ObjectID,
						"UpdateID=" .. lul_settings.UpdateID}})
end

function actionAVTransportRemoveTrackRangeFromQueue( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.RemoveTrackRangeFromQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"UpdateID=" .. lul_settings.UpdateID,
						"StartingIndex=" .. lul_settings.StartingIndex,
						"NumberOfTracks=" .. lul_settings.NumberOfTracks}})
end

function actionAVTransportRemoveAllTracksFromQueue( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.RemoveAllTracksFromQueue({InstanceID=instanceId})
end

function actionAVTransportSaveQueue( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.SaveQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"Title=" .. lul_settings.Title,
						"ObjectID=" .. lul_settings.ObjectID}})
end

function actionAVTransportBackupQueue( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.BackupQueue({InstanceID=instanceId})
end

function actionAVTransportChangeTransportSettings( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.ChangeTransportSettings(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"NewTransportSettings=" .. lul_settings.NewTransportSettings,
						"CurrentAVTransportURI=" .. lul_settings.CurrentAVTransportURI}})
end

function actionAVTransportConfigureSleepTimer( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.ConfigureSleepTimer(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"NewSleepTimerDuration=" .. lul_settings.NewSleepTimerDuration}})
end

function actionAVTransportRunAlarm( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
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
end

function actionAVTransportStartAutoplay( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.StartAutoplay(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"ProgramURI=" .. lul_settings.ProgramURI,
						"ProgramMetaData=" .. lul_settings.ProgramMetaData,
						"Volume=" .. lul_settings.Volume,
						"IncludeLinkedZones=" .. lul_settings.IncludeLinkedZones,
						"ResetVolumeAfter=" .. lul_settings.ResetVolumeAfter}})
end

function actionAVTransportSnoozeAlarm( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.SnoozeAlarm(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"Duration=" .. lul_settings.Duration}})
end

function actionAVTransportSetCrossfadeMode( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local device, uuid = controlByCoordinator(UUIDs[lul_device])
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
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
end

function actionAVTransportNotifyDeletedURI( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.NotifyDeletedURI(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"DeletedURI=" .. lul_settings.DeletedURI}})
end

function actionAVTransportBecomeCoordinatorSG( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID=instanceId})
end

function actionAVTransportBecomeGroupCoordinator( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
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
end

function actionAVTransportBecomeGCAndSource( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
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
end

function actionAVTransportChangeCoordinator( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.ChangeCoordinator(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"CurrentCoordinator=" .. lul_settings.CurrentCoordinator,
						"NewCoordinator=" .. lul_settings.NewCoordinator,
						"NewTransportSettings=" .. lul_settings.NewTransportSettings}})
end

function actionAVTransportDelegateGCTo( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if not AVTransport then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.DelegateGroupCoordinationTo(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"NewCoordinator=" .. lul_settings.NewCoordinator,
						"RejoinGroup=" .. lul_settings.RejoinGroup}})
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:upnp-org:serviceId:RenderingControl

--]]

function actionRCSetMute( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local uuid = UUIDs[lul_device]
	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return false
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
end

function actionRCResetBasicEQ( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.ResetBasicEQ({InstanceID=instanceId})
end

function actionRCResetExtEQ( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.ResetExtEQ(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "EQType=" .. lul_settings.EQType}})
end

function actionRCSetVolume( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local uuid = UUIDs[lul_device]
	if tostring(dataTable[uuid].OutputFixed or 0) ~= "0" then
		W("SetVolume on %1 (#%2) not possible, configured for fixed output volume (action ignored)",
			luup.devices[lul_device].description, lul_device)
		return
	end

	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return false
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local desiredVolume = tonumber(defaultValue(lul_settings, "DesiredVolume", "5"))
	local channel = defaultValue(lul_settings, "Channel", "Master")

	Rendering.SetVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "DesiredVolume=" .. desiredVolume}})

	refreshVolumeNow(uuid)
end

function actionRCSetRelativeVolume( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local uuid = UUIDs[lul_device]
	if tostring(dataTable[uuid].OutputFixed or 0) ~= "0" then
		W("SetRelativeVolume on %1 (#%2) not possible, configured for fixed output volume (action ignored)",
			luup.devices[lul_device].description, lul_device)
		return
	end

	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return false
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local channel = defaultValue(lul_settings, "Channel", "Master")

	Rendering.SetRelativeVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "Adjustment=" .. lul_settings.Adjustment}})

	refreshVolumeNow(uuid)
end

function actionRCSetVolumeDB( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local uuid = UUIDs[lul_device]
	if tostring(dataTable[uuid].OutputFixed or 0) ~= "0" then
		W("SetVolumeDB on %1 (#%2) not possible, configured for fixed output volume (action ignored)",
			luup.devices[lul_device].description, lul_device)
		return
	end

	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return false
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
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetBass(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "DesiredBass=" .. lul_settings.DesiredBass}})
end

function actionRCSetTreble( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetTreble(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "DesiredTreble=" .. lul_settings.DesiredTreble}})
end

function actionRCSetEQ( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetEQ(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "EQType=" .. lul_settings.EQType,
					 "DesiredValue=" .. lul_settings.DesiredValue}})
end

function actionRCSetLoudness( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetLoudness(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. lul_settings.Channel,
					 "DesiredLoudness=" .. lul_settings.DesiredLoudness}})
end

function actionRCSetOutputFixed( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetOutputFixed(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "DesiredFixed=" .. lul_settings.DesiredFixed}})
end

function actionRCRampToVolume( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.RampToVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. lul_settings.Channel,
					 "RampType=" .. lul_settings.RampType,
					 "DesiredVolume=" .. lul_settings.DesiredVolume,
					 "ResetVolumeAfter=" .. lul_settings.ResetVolumeAfter,
					 "ProgramURI=" .. lul_settings.ProgramURI}})
end

function actionRCRestoreVolumePriorToRamp( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.RestoreVolumePriorToRamp(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. lul_settings.Channel}})
end

function actionRCSetChannelMap( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if not Rendering then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetChannelMap(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "ChannelMap=" .. lul_settings.ChannelMap}})
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:upnp-org:serviceId:GroupRenderingControl

--]]

function actionGRCSetGroupMute( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local GroupRendering = upnp.getService(uuid, UPNP_GROUP_RENDERING_CONTROL_SERVICE)
	if (GroupRendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local desiredMute = defaultValue(lul_settings, "DesiredMute", "0")

	GroupRendering.SetGroupMute(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "DesiredMute=" .. desiredMute}})
end

function actionGRCSetGroupVolume( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local GroupRendering = upnp.getService(uuid, UPNP_GROUP_RENDERING_CONTROL_SERVICE)
	if (GroupRendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local desiredVolume = tonumber(defaultValue(lul_settings, "DesiredVolume", "5"))

	GroupRendering.SetGroupVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "DesiredVolume=" .. desiredVolume}})
end

function actionGRCSetRelativeGroupVolume( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local GroupRendering = upnp.getService(uuid, UPNP_GROUP_RENDERING_CONTROL_SERVICE)
	if (GroupRendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	GroupRendering.SetRelativeGroupVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Adjustment=" .. lul_settings.Adjustment}})
end

function actionGRCSnapshotGroupVolume( lul_device, lul_settings )
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	local _, uuid = controlByCoordinator(UUIDs[lul_device])
	local GroupRendering = upnp.getService(uuid, UPNP_GROUP_RENDERING_CONTROL_SERVICE)
	if (GroupRendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	GroupRendering.SnapshotGroupVolume(
		 {InstanceID=instanceId})
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:micasaverde-com:serviceId:HaDevice1

--]]

function actionPoll( lul_device, lul_settings ) -- luacheck: ignore 212
	assert(luup.devices[lul_device].device_type == SONOS_ZONE_DEVICE_TYPE)
	updateNow(lul_device)
	return 4,0
end
