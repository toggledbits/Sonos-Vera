--[[
	Sonos Plugin for Vera and openLuup
	Current maintainer: rigpapa https://community.getvera.com/u/rigpapa/summary
	Github repository: https://github.com/toggledbits/Sonos-Vera
	For license information, please see the above repository.
--]]

module( "L_Sonos1", package.seeall )

PLUGIN_NAME = "Sonos"
PLUGIN_VERSION = "1.5-20053"
PLUGIN_ID = 4226

local DEBUG_MODE = false	-- Don't hardcode true--use state variable config

local MIN_UPNP_VERSION = 19191	-- Minimum version of L_SonosUPnP that works
local MIN_TTS_VERSION = 19287	-- Minimum version of L_SonosTTS that works

local MSG_CLASS = "Sonos"
local isOpenLuup = false

local taskHandle = -1
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
if type( upnp ) ~= "table" then _G.error "Sonos: invalid installation; the L_SonosUPnP module could not be loaded." end
local _,tts = pcall( require, "L_SonosTTS" )
if type( tts ) ~= "table" then tts = nil end

local url = require "socket.url"
local lom = require "lxp.lom"

-- Table of Sonos IP addresses indexed by Vera devices
local ip = {}
local port
local descriptionURL
local iconURL

local HADEVICE_SID = "urn:micasaverde-com:serviceId:HaDevice1"
local SONOS_SID = "urn:micasaverde-com:serviceId:Sonos1"
local SONOS_DEVICE_TYPE = "urn:schemas-micasaverde-com:device:Sonos:1"

local EventSubscriptions = {
	{ service = UPNP_AVTRANSPORT_SERVICE,
	eventVariable = "LastChange",
	actionName = "NotifyAVTransportChange",
	id = "",
	expiry = "" },
	{ service = UPNP_RENDERING_CONTROL_SERVICE,
	eventVariable = "LastChange",
	actionName = "NotifyRenderingChange",
	id = "",
	expiry = "" },
	{ service = UPNP_ZONEGROUPTOPOLOGY_SERVICE,
	eventVariable = "ZoneGroupState",
	actionName = "NotifyZoneGroupTopologyChange",
	id = "",
	expiry = "" },
	{ service = UPNP_MR_CONTENT_DIRECTORY_SERVICE,
	eventVariable = "ContainerUpdateIDs",
	actionName = "NotifyContentDirectoryChange",
	id = "",
	expiry = "" }
}

local PLUGIN_ICON = "Sonos.png"

local QUEUE_URI = "x-rincon-queue:%s#0"

local playbackCxt = {}
local sayPlayback = {}

-- Zone group topology (set by updateZoneInfo())
local zoneInfo = false

-- Table of Sonos UUIDs indexed by Vera devices
local UUIDs = {}

local groupsState = ""

local sonosServices = {}

-- Tables indexed by Sonos UUIDs
local metaDataKeys = {}
local dataTable = {}

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
	CurrentService = SONOS_SID,
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

	Mute = UPNP_RENDERING_CONTROL_SID,
	Volume = UPNP_RENDERING_CONTROL_SID,

	SavedQueues = UPNP_MR_CONTENT_DIRECTORY_SID,
	FavoritesRadios = UPNP_MR_CONTENT_DIRECTORY_SID,
	Favorites = UPNP_MR_CONTENT_DIRECTORY_SID,
	Queue = UPNP_MR_CONTENT_DIRECTORY_SID,

	GroupCoordinator = SONOS_SID,
	ZonePlayerUUIDsInGroup = UPNP_ZONEGROUPTOPOLOGY_SID,
	ZoneGroupState = UPNP_ZONEGROUPTOPOLOGY_SID,

	SonosOnline = SONOS_SID,
	ZoneName = UPNP_DEVICE_PROPERTIES_SID,
	SonosID = UPNP_DEVICE_PROPERTIES_SID,
	SonosModelName = SONOS_SID,
	SonosModel = SONOS_SID,
	SonosModelNumber = SONOS_SID,
	PollDelays = SONOS_SID,
	PluginVersion = SONOS_SID,
	Enabled = SONOS_SID,

	ProxyUsed = SONOS_SID
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

local function log(stuff, level)
	luup.log(string.format("%s: %s", MSG_CLASS, tostring(stuff)), level or 50)
end

local function warning(stuff)
	log("warning: " .. tostring(stuff), 2)
end

local function error(stuff)
	log("error: " .. tostring(stuff), 1)
end

local function debug(stuff)
	if DEBUG_MODE then log("debug: " .. tostring(stuff)) end
end

-- Clone table (shallow copy)
local function clone( sourceArray )
	local newArray = {}
	for ix,element in pairs( sourceArray or {} ) do
		newArray[ix] = element
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

-- Initialize a variable if it does not already exist.
local function initVar( name, dflt, dev, sid )
	assert( dev ~= nil )
	sid = sid or SONOS_SID
	local currVal = luup.variable_get( sid, name, dev )
	if currVal == nil then
		luup.variable_set( sid, name, tostring(dflt), dev )
	end
	return currVal
end

-- Set variable, only if value has changed.
local function setVar( sid, name, val, dev )
	assert( dev ~= nil )
	sid = sid or SONOS_SID
	val = (val == nil) and "" or tostring(val)
	local s = luup.variable_get( sid, name, dev ) or ""
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
	local s = luup.variable_get( sid or SONOS_SID, name, dev )
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
			warning("This version of the Sonos plugin requires openLuup 2018.11.21 or higher")
			return "./" -- punt
		end
		return loader.find_file( "L_Sonos1.lua" ):gsub( "L_Sonos1.lua$", "" )
	end
	return "/etc/cmh-ludl/"
end

local function task(text, mode)
	luup.log("task " .. text)
	if (mode == TASK_ERROR_PERM) then
		taskHandle = luup.task(text, TASK_ERROR, MSG_CLASS, taskHandle)
	else
		taskHandle = luup.task(text, mode, MSG_CLASS, taskHandle)

		-- Clear the previous error, since they're all transient
		if (mode ~= TASK_SUCCESS) then
			luup.call_delay("clearTask", 30, "", false)
		end
	end
end

--
-- Has to be "non-local" in order for MiOS to call it :(
--
function clearTask()
	task("Clearing...", TASK_SUCCESS)
end

local function defaultValue(arr, val, default)
	if (arr == nil or arr[val] == nil or arr[val] == "") then
		return default
	else
		return arr[val]
	end
end

local function setData(name, value, deviceId, default)
	local uuid = UUIDs[deviceId] or ""
	if (uuid ~= "" and dataTable[uuid] ~= nil) then
		dataTable[uuid][name] = value
	end

	if (deviceId == 0 or variableSidTable[name] == nil) then
		error(string.format("setData() can't set %s on %d no SID!", tostring(name), deviceId))
		return (default or false)
	end

	local curValue = luup.variable_get(variableSidTable[name], name, deviceId)

	if ((value ~= curValue) or (curValue == nil)) then
		luup.variable_set(variableSidTable[name], name, value, deviceId)
		return true
	else
		return (default or false)
	end
end

local function initData(name, value, deviceId)
	local uuid = UUIDs[deviceId]
	if (uuid ~= "" and dataTable[uuid] ~= nil) then
		dataTable[uuid][name] = value
	end

	local curValue = luup.variable_get(variableSidTable[name], name, deviceId)
	if curValue == nil then
		luup.variable_set(variableSidTable[name], name, value, deviceId)
		return value
	end
	return curValue
end

local function setVariableValue(serviceId, name, value, deviceId)
	if (deviceId ~= 0) then
		luup.variable_set(serviceId, name, value, deviceId)
	end
end

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
function updateZoneInfo( device )
	debug("updateZoneInfo for " .. tostring(device))
	zoneInfo = { zones={}, groups={} }
	local zs = getVar( "ZoneGroupState", "<ZoneGroupState/>", device, UPNP_ZONEGROUPTOPOLOGY_SID )
	debug("updateZoneInfo() zone info is \r\n"..tostring(zs))
	local root = lom.parse( zs )
	assert( root.tag == "ZoneGroupState" )
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
	debug("updateZoneInfo() updated zoneInfo: " .. dump(zoneInfo))
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

local function getIPFromUUID(uuid)
	local location = (zoneInfo.zones[uuid] or {}).Location
	if location then
		return location:match( "^https?://([^:/]+)")
	end
	return nil
end

-- Return zoneInfo group data for group of which zoneUUID is a member
local function getZoneGroup( zoneUUID )
	local zi = zoneInfo.zones[zoneUUID]
	if zi then
		debug("getZoneGroup() group info for "..zi.Group.." is "..dump(zoneInfo.groups[zi.Group]))
		return zoneInfo.groups[zi.Group]
	end
	warning("No zoneInfo for zone "..tostring(zoneUUID))
	return nil
end

local function getZoneCoordinator( zoneUUID )
	local gr = getZoneGroup( zoneUUID ) or {}
	return (gr or {}).Coordinator, gr
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

local function deviceIsOnline(device)
	local changed = setData("SonosOnline", "1", device, false)
	if changed then
		log("Setting device #" .. tostring(device) .. " on line.")
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), device)
	end
	return changed
end

local function deviceIsOffline(device)
	local changed = setData("SonosOnline", "0", device, false)
	if changed then
		warning("Setting device #" .. tostring(device) .. " to off-line state.")
		groupsState = "<ZoneGroups></ZoneGroups>"

		changed = setData("TransportState", "STOPPED",  device, changed)
		changed = setData("TransportStatus", "KO",  device, changed)
		changed = setData("TransportPlaySpeed", "1",  device, changed)
		changed = setData("CurrentPlayMode", "NORMAL", device, changed)
		changed = setData("CurrentCrossfadeMode", "0", device, changed)
		changed = setData("CurrentTransportActions", "", device, changed)
		changed = setData("NumberOfTracks", "NOT_IMPLEMENTED", device, changed)
		changed = setData("CurrentMediaDuration", "NOT_IMPLEMENTED", device, changed)
		changed = setData("AVTransportURI", "", device, changed)
		changed = setData("AVTransportURIMetaData", "", device, changed)
		changed = setData("CurrentRadio", "", device, changed)
		changed = setData("CurrentService", "", device, changed)
		changed = setData("CurrentTrack", "NOT_IMPLEMENTED", device, changed)
		changed = setData("CurrentTrackDuration", "NOT_IMPLEMENTED", device, changed)
		changed = setData("CurrentTrackURI", "", device, changed)
		changed = setData("CurrentTrackMetaData", "", device, changed)
		changed = setData("CurrentStatus", "Offline", device, changed)
		changed = setData("CurrentTitle", "", device, changed)
		changed = setData("CurrentArtist", "", device, changed)
		changed = setData("CurrentAlbum", "", device, changed)
		changed = setData("CurrentDetails", "", device, changed)
		changed = setData("CurrentAlbumArt", PLUGIN_ICON, device, changed)
		changed = setData("RelativeTimePosition", "NOT_IMPLEMENTED", device, changed)
		changed = setData("Volume", "0", device, changed)
		changed = setData("Mute", "0", device, changed)
		changed = setData("SavedQueues", "", device, changed)
		changed = setData("FavoritesRadios", "", device, changed)
		changed = setData("Favorites", "", device, changed)
		changed = setData("Queue", "", device, changed)
		changed = setData("GroupCoordinator", "", device, changed)
		changed = setData("ZonePlayerUUIDsInGroup", "", device, changed)
		changed = setData("ZoneGroupState", groupsState, device, changed)
		updateZoneInfo( device )

		if changed then
			setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), device)
		end

		if device ~= 0 then
			upnp.cancelProxySubscriptions(EventSubscriptions)
		end
	end
end

local function commsFailure(device, text)
	warning("Sonos device #" .. tostring(device) .. " (" .. tostring((luup.devices[device] or {}).description) ..
		" @" .. (luup.attr_get("ip", device or -1) or "") .. ") comm failure. " .. tostring(text or ""))
	deviceIsOffline(device)
end

local function getSonosServiceId(serviceName)
	local serviceId = nil
	for k, v in pairs(sonosServices) do
		if (v == serviceName) then
			serviceId = k
			break
		end
	end
	return serviceId
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
			serviceName = sonosServices[serviceId] or ""
		end
	end
	return serviceName, serviceId
end

local function updateServicesMetaDataKeys(device, id, key)
	local uuid = UUIDs[device]
	if (id ~= nil and key ~= "" and metaDataKeys[uuid][id] ~= key) then
		metaDataKeys[uuid][id] = key
		local data = ""
		for k, v in pairs(metaDataKeys[uuid]) do
			data = data .. string.format('%s=%s\n', k, v)
		end
		setVariableValue(SONOS_SID, "SonosServicesKeys", data, device)
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), device)
	end
end

local function loadServicesMetaDataKeys(device)
	local k = {}
	local elts = getVar("SonosServicesKeys", "", device)
	for token, value in elts:gmatch("([^=]+)=([^\n]+)\n") do
		k[token] = value
	end
	return k
end

local function extractDataFromMetaData(device, currentUri, currentUriMetaData, trackUri, trackUriMetaData)
	local statusString, info, title, title2, artist, album, details, albumArt, desc
	local uuid = UUIDs[device]
	_, title, _, _, _, _, desc = getSimpleDIDLStatus(currentUriMetaData)
	info, title2, artist, album, details, albumArt, _ = getSimpleDIDLStatus(trackUriMetaData)
	local service, serviceId = getServiceFromURI(currentUri, trackUri)
	updateServicesMetaDataKeys(device, serviceId, desc)
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
		albumArt = url.absolute(string.format("http://%s:%s/", ip[uuid], port), albumArt)
	elseif (serviceId ~= nil) then
		albumArt = string.format("http://%s:%s/getaa?s=1&u=%s", ip[uuid], port, url.escape(currentUri))
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

local setup -- forward declaration
local function refreshNow(device, force, refreshQueue)
	debug("refreshNow: device=" .. device)

	if upnp.proxyVersionAtLeast(1) and not force then
		return ""
	end

	local uuid = UUIDs[device]
	if (uuid == nil or uuid == "") then
		return ""
	end

	local status, tmp
	local changed = false
	local statusString, info, title, title2, artist, album, details, albumArt
	local currentUri, currentUriMetaData, trackUri, trackUriMetaData, service

	-- PHR???
	local DeviceProperties = upnp.getService(uuid, UPNP_DEVICE_PROPERTIES_SERVICE)
	if DeviceProperties then
		status, tmp = DeviceProperties.GetZoneInfo({})
	else
		debug("Can't find device properties service " .. tostring(UPNP_DEVICE_PROPERTIES_SERVICE))
	end

	-- Update network and group information
	local ZoneGroupTopology = upnp.getService(uuid, UPNP_ZONEGROUPTOPOLOGY_SERVICE)
	if ZoneGroupTopology then
		debug("refreshNow() refreshing zone group topology")
		status, tmp = ZoneGroupTopology.GetZoneGroupState({})
		if not status then
			commsFailure(device, tmp)
			return ""
		end
		if deviceIsOnline(device) then
			setup(device, true)
		end
		groupsState = upnp.extractElement("ZoneGroupState", tmp, "")
		changed = setData("ZoneGroupState", groupsState, device, changed)
		if changed or not zoneInfo then
			updateZoneInfo( device )
		end
		local members, coordinator = getGroupInfos( uuid )
		changed = setData("ZonePlayerUUIDsInGroup", members, device, changed)
		changed = setData("GroupCoordinator", coordinator or "", device, changed)
	end

	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if AVTransport then
		debug("refreshNow() refreshing transport state")
		-- GetCurrentTransportState  (PLAYING, STOPPED, etc)
		status, tmp = AVTransport.GetTransportInfo({InstanceID="0"})
		if (status ~= true) then
			commsFailure(device, tmp)
			return ""
		end
		changed = setData("TransportState", upnp.extractElement("CurrentTransportState", tmp, ""), device, changed)
		changed = setData("TransportStatus", upnp.extractElement("CurrentTransportStatus", tmp, ""), device, changed)
		changed = setData("TransportPlaySpeed", upnp.extractElement("CurrentSpeed", tmp, ""), device, changed)

		-- Get Playmode (NORMAL, REPEAT_ALL, SHUFFLE_NOREPEAT, SHUFFLE)
		_, tmp = AVTransport.GetTransportSettings({InstanceID="0"})
		changed = setData("CurrentPlayMode", upnp.extractElement("PlayMode", tmp, ""), device, changed)

		-- Get Crossfademode
		_, tmp = AVTransport.GetCrossfadeMode({InstanceID="0"})
		changed = setData("CurrentCrossfadeMode", upnp.extractElement("CrossfadeMode", tmp, ""), device, changed)

		-- Get Current Transport Actions (a CSV of valid Transport Action/Transitions)
		_, tmp = AVTransport.GetCurrentTransportActions({InstanceID="0"})
		changed = setData("CurrentTransportActions", upnp.extractElement("Actions", tmp, ""), device, changed)

		-- Get Media Information
		_, tmp = AVTransport.GetMediaInfo({InstanceID="0"})
		currentUri = upnp.extractElement("CurrentURI", tmp, "")
		currentUriMetaData = upnp.extractElement("CurrentURIMetaData", tmp, "")
		changed = setData("NumberOfTracks", upnp.extractElement("NrTracks", tmp, "NOT_IMPLEMENTED"), device, changed)
		changed = setData("CurrentMediaDuration", upnp.extractElement("MediaDuration", tmp, "NOT_IMPLEMENTED"), device, changed)
		changed = setData("AVTransportURI", currentUri, device, changed)
		changed = setData("AVTransportURIMetaData", currentUriMetaData, device, changed)

		-- Get Current URI - song or radio station etc
		_, tmp = AVTransport.GetPositionInfo({InstanceID="0"})
		trackUri = upnp.extractElement("TrackURI", tmp, "")
		trackUriMetaData = upnp.extractElement("TrackMetaData", tmp, "")
		changed = setData("CurrentTrack", upnp.extractElement("Track", tmp, "NOT_IMPLEMENTED"), device, changed)
		changed = setData("CurrentTrackDuration", upnp.extractElement("TrackDuration", tmp, "NOT_IMPLEMENTED"), device, changed)
		changed = setData("CurrentTrackURI", trackUri, device, changed)
		changed = setData("CurrentTrackMetaData", trackUriMetaData, device, changed)
		changed = setData("RelativeTimePosition", upnp.extractElement("RelTime", tmp, "NOT_IMPLEMENTED"), device, changed)

		service, title, statusString, title2, artist, album, details, albumArt =
			extractDataFromMetaData(device, currentUri, currentUriMetaData, trackUri, trackUriMetaData)

		changed = setData("CurrentService", service, device, changed)
		changed = setData("CurrentRadio", title, device, changed)
		changed = setData("CurrentStatus", statusString, device, changed)
		changed = setData("CurrentTitle", title2, device, changed)
		changed = setData("CurrentArtist", artist, device, changed)
		changed = setData("CurrentAlbum", album, device, changed)
		changed = setData("CurrentDetails", details, device, changed)
		changed = setData("CurrentAlbumArt", albumArt, device, changed)
	end

	local Rendering = upnp.getService(uuid, UPNP_RENDERING_CONTROL_SERVICE)
	if Rendering then
		debug("refreshNow() refreshing rendering state")
		-- Get Mute status
		status, tmp = Rendering.GetMute({OrderedArgs={"InstanceID=0", "Channel=Master"}})
		if status ~= true then
			commsFailure(device, tmp)
			return ""
		end
		changed = setData("Mute", upnp.extractElement("CurrentMute", tmp, ""), device, changed)

		-- Get Volume
		status, tmp = Rendering.GetVolume({OrderedArgs={"InstanceID=0", "Channel=Master"}})
		if status ~= true then
			commsFailure(device, tmp)
			return ""
		end
		changed = setData("Volume", upnp.extractElement("CurrentVolume", tmp, ""), device, changed)
	end

	-- Sonos queue
	if refreshQueue then
		debug("refreshNow() refreshing queue")
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

local function refreshVolumeNow(device)
	debug("refreshVolumeNow: start")

	if upnp.proxyVersionAtLeast(1) then
		return
	end
	local Rendering = upnp.getService(UUIDs[device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local status, tmp, changed

	-- Get Volume
	status, tmp = Rendering.GetVolume({OrderedArgs={"InstanceID=0", "Channel=Master"}})

	if (status ~= true) then
		commsFailure(device, tmp)
		return
	end

	changed = setData("Volume", upnp.extractElement("CurrentVolume", tmp, ""), device, false)

	if changed then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), device)
	end
end

local function refreshMuteNow(device)
	debug("refreshMuteNow: start")

	if upnp.proxyVersionAtLeast(1) then
		return
	end
	local Rendering = upnp.getService(UUIDs[device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local status, tmp, changed

	-- Get Mute status
	status, tmp = Rendering.GetMute({OrderedArgs={"InstanceID=0", "Channel=Master"}})

	if (status ~= true) then
		commsFailure(device, tmp)
		return
	end

	changed = setData("Mute", upnp.extractElement("CurrentMute", tmp, ""), device, false)

	if changed then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), device)
	end
end

local function controlAnotherZone(targetUUID, sourceDevice)
	debug("controlAnotherZone targetUUID=" .. targetUUID .. " sourceDevice=" .. sourceDevice)
	local device = nil
	local sourceUUID = UUIDs[sourceDevice or ""]
	if targetUUID == sourceUUID then
		debug("controlAnotherZone() self-control")
		device = sourceDevice
	else
		local targetIP = getIPFromUUID(targetUUID)
		debug("controlAnotherZone targetIP="..tostring(targetIP))
		if targetIP then
			-- Search known devices
			for k,v in pairs( UUIDs ) do
				if v == targetUUID then
					device = k
					break
				end
			end
			if not device then
				-- Search all devices
				for nd,v in pairs( luup.devices ) do
					if v.device_type == SONOS_DEVICE_TYPE and luup.attr_get( 'ip', nd ) == targetIP then
						-- Found!
						device = nd
						break
					end
				end
			end
			device = device or 0
			debug("controlAnotherZone() device for " .. targetIP .. " is " .. device)
			UUIDs[device] = targetUUID
			ip[device] = targetIP
			metaDataKeys[targetUUID] = metaDataKeys[sourceUUID]
			dataTable[targetUUID] = {}
			if (ip[targetUUID] == nil or ip[targetUUID] ~= targetIP) then
				debug("controlAnotherZone resetting UPnP services for "..tostring(targetIP))
				local descrURL = string.format(descriptionURL, targetIP, port)
				upnp.resetServices(targetUUID)
				local status = upnp.setup(descrURL,
									"urn:schemas-upnp-org:device:ZonePlayer:1",
									{ },
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
				if (status == true) then
					ip[targetUUID] = targetIP
					debug("controlAnotherZone OK, that worked... what about setting device???")
				else
					ip[targetUUID] = nil
					device = nil
				end
			end
		end
	end
	debug("controlAnotherZone result=" .. tostring(device))
	return device
end

local function controlByCoordinator(device)
	local resDevice = nil
	local resUUID
	local coordinator = getZoneCoordinator( UUIDs[device] ) or ""
	if coordinator then
		resDevice = controlAnotherZone(coordinator, device)
		resUUID = coordinator
	end
	if not resDevice then
		resDevice = device
		resUUID = UUIDs[device]
	end
	return resDevice, resUUID
end

-- ??? rigpapa: there is brokenness in the handling of the title variable throughout,
--              with interior local redeclarations shadowing the exterior declaration, it's unclear
--              if the inner values attained are needed in the outer scopes. This needs
--              to be studied carefully before cleanup.
local function decodeURI(device, coordinator, uri)
	debug("decodeURI device "..tostring(device).." coord "..tostring(coordinator)..
		" uri "..tostring(uri))
	local uuid = nil
	local track = nil
	local uriMetaData = ""
	local serviceId
	local title = nil
	local controlByGroup = true
	local localUUID = UUIDs[device]
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
		debug("data from server: " .. (xml or "nil"))
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

	debug("uri: " .. tostring(uri))
	debug("uriMetaData: " .. tostring(uriMetaData))
	return uri, uriMetaData, track, controlByGroup, requireQueueing
end

local groupDevices -- forward declaration
local function playURI(device, instanceId, uri, speed, volume, uuids, sameVolumeForAll, enqueueMode, newGroup, controlByGroup)
	log("Playing "..tostring(uri).." on "..tostring(device).."/"..tostring(instanceId))
	uri = url.unescape(uri)

	local uriMetaData, track, controlByGroup2, requireQueueing, uuid, status, tmp, position
	local channel = "Master"

	if newGroup then
		controlByGroup = false
	end

	if controlByGroup then
		_, uuid = controlByCoordinator(device)
	else
		uuid = UUIDs[device]
	end

	uri, uriMetaData, track, controlByGroup2, requireQueueing = decodeURI(device, uuid, uri)
	if (controlByGroup and not controlByGroup2) then
		-- ??? rigpapa ...and then what are the controlByGroup variables used for???
		controlByGroup = false -- luacheck: ignore 311
		uuid = UUIDs[device]
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
			debug("playURI() clearing queue")
			AVTransport.RemoveAllTracksFromQueue({InstanceID=instanceId})
		end

		if enqueueMode == "ENQUEUE_AT_FIRST" or enqueueMode == "ENQUEUE_AT_FIRST_AND_PLAY" then
			debug("playURI() enqueueing at first")
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
			debug("playURI() enqueueing at "..position)
			status, tmp = AVTransport.AddURIToQueue(
				 {OrderedArgs={"InstanceID=" .. instanceId,
							 "EnqueuedURI=" .. uri,
							 "EnqueuedURIMetaData=" .. uriMetaData,
							 "DesiredFirstTrackNumberEnqueued=" .. position,
							 "EnqueueAsNext=false"}})
		elseif enqueueMode == "ENQUEUE" or enqueueMode == "ENQUEUE_AND_PLAY"
				or enqueueMode == "REPLACE_QUEUE" or enqueueMode == "REPLACE_QUEUE_AND_PLAY" then
			debug("playURI() appending to queue")
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
			debug("playURI() creating new group")
			AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID=instanceId})

			-- If uuids is an array containing other than just the controlling device, group them.
			if uuids and not (#uuids == 1 and uuids[1] == uuid) then
				groupDevices(device, instanceId, uuids, sameVolumeForAll and volume or nil)
			end
		end

		debug("playURI() setting URI to "..tostring(uri).." meta "..tostring(uriMetaData))
		AVTransport.SetAVTransportURI(
			{OrderedArgs={"InstanceID=" .. instanceId,
							"CurrentURI=" .. uri,
							"CurrentURIMetaData=" .. uriMetaData}})

		if tonumber(track or "") then
			debug("playURI() setting track "..tostring(track))
			AVTransport.Seek(
				 {OrderedArgs={"InstanceID=" .. instanceId,
							 "Unit=TRACK_NR",
							 "Target=" .. track}})
		end

		if tonumber(volume or "") and Rendering then
			debug("playURI() setting volume "..tostring(volume))
			Rendering.SetVolume(
				{OrderedArgs={"InstanceID=" .. instanceId,
								"Channel=" .. channel,
								"DesiredVolume=" .. volume}})
		end

		speed = speed or "1"
		if tonumber(speed) then
			debug("playURI() starting play")
			AVTransport.Play(
				 {OrderedArgs={"InstanceID=" .. instanceId,
							 "Speed=" .. speed}})
		end
	end
end

groupDevices = function(device, instanceId, uuids, volume)
	debug("groupDevices() args="..dump({device=device,instanceId=instanceId,uuids=uuids,volume=volume}))
	local localUUID = UUIDs[device]
	for _,uuid in ipairs( uuids or {} ) do
		if uuid ~= localUUID then
			local device2 = controlAnotherZone(uuid, device)
			if device2 then
				playURI(device2, instanceId, "x-rincon:" .. UUIDs[device], "1", volume, nil, false, nil, false, false)
			end
		end
	end
end

local function savePlaybackContexts(device, uuids)
	debug("savePlaybackContexts: device=" .. device .. " uuids=" .. dump(uuids))
	local cxt = {}
	local devices = {}
	for _,uuid in ipairs( uuids ) do
		local device2 = controlAnotherZone(uuid, device)
		if device2 then
			refreshNow(device2, true, false) -- ??? PHR: ineffective, the operation is basically asynchronous, so this is a race condition that probably always loses
			cxt[uuid] = {}
			cxt[uuid].Device = device2
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
			table.insert( devices, device2 )
		end
	end

	return { context = cxt, devices = devices }
end

local function restorePlaybackContext(device, uuid, cxt)
	debug("restorePlaybackContext: device=" .. device .. " uuid=" .. uuid .. " cxt=" .. dump(cxt))
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

	if (Rendering ~= nil) then
		Rendering.SetMute(
			{OrderedArgs={"InstanceID=" .. instanceId,
							"Channel=" .. channel,
							"DesiredMute=" .. cxt.Mute}})

		Rendering.SetVolume(
			{OrderedArgs={"InstanceID=" .. instanceId,
							"Channel=" .. channel,
							"DesiredVolume=" .. cxt.Volume}})
	end

	if (AVTransport ~= nil
			and cxt.AVTransportURI ~= ""
			and (cxt.TransportState == "PLAYING"
					 or cxt.TransportState == "TRANSITIONING")) then
		AVTransport.Play(
			{OrderedArgs={"InstanceID=" .. instanceId,
							"Speed=" .. cxt.TransportPlaySpeed}})
	end

	if (device or 0) ~= 0 then
		refreshNow(device, false, true)
	end
end

local function restorePlaybackContexts(device, playCxt)
	debug("restorePlaybackContexts: device=" .. device)
	-- local instanceId="0"
	-- local channel="Master"
	-- local localUUID = UUIDs[device]
	-- local device2

	if not playCxt then
		-- warning("Please save the context before restoring it!")
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
local function joinGroup(device, zone)
	local localUUID = UUIDs[device]
	local uuid = zone:match("RINCON_%x+") and zone or getUUIDFromZoneName(zone)
	if uuid ~= nil then
		local groupInfo = zoneInfo.groups[zoneInfo.zones[uuid].Group]
		for _,member in ipairs( (groupInfo or {}).members or {} ) do
			if member.UUID == localUUID then return end -- already in group
		end
		playURI(device, "0", "x-rincon:" .. groupInfo.Coordinator, "1", nil, nil, false, nil, false, false)
	end
end

local function leaveGroup(device)
	local AVTransport = upnp.getService(UUIDs[device], UPNP_AVTRANSPORT_SERVICE)
	if AVTransport ~= nil then
		AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID="0"})
	end
end

local function updateGroupMembers(device, members)
	local prevMembers, coordinator = getGroupInfos(UUIDs[device])
	local targets = {}
	if members:upper() == "ALL" then
		_, targets = getAllUUIDs()
	else
		for zone in members:gmatch("[^,]+") do
			local uuid
			if zone:match("RINCON_%x+") then
				uuid = zone
			else
				uuid = getUUIDFromZoneName(zone)
			end
			if ( uuid or "" ) ~= "" then
				targets[uuid] = true
			end
		end
	end

	-- Make any new members part of the group
	for uuid in pairs( targets ) do
		if not prevMembers:find(uuid) then
			local device2 = controlAnotherZone(uuid, device)
			if device2 then
				playURI(device2, "0", "x-rincon:" .. coordinator, "1", nil, nil, false, nil, false, false)
			end
		end
	end

	-- Remove previous members that are no longer in group
	for uuid in prevMembers:gmatch("RINCON_%x+") do
		if not targets[uuid] then
			local device2 = controlAnotherZone(uuid, device)
			if device2 then
				local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
				if AVTransport then
					AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID="0"})
				end
			end
		end
	end
end

local function pauseAll(device)
	local uuids = getAllUUIDs()
	for uuid in uuids:gmatch("RINCON_%x+") do
		local device2 = controlAnotherZone(uuid, device)
		if device2 then
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
	local ttsrev = getVarNumeric("_ttsrev", 0, device)
	local lang = getVar("DefaultLanguageTTS", "", device, SONOS_SID, true)
	if lang == "" then
		lang = "en"
	elseif lang == "en" then
		setVar(SONOS_SID, "DefaultLanguageTTS", "", device) -- restore default
	end
	local engine = getVar("DefaultEngineTTS", "", device, SONOS_SID, true)
	if engine == "" then
		engine = "GOOGLE"
	elseif engine == "GOOGLE" then
		setVar(SONOS_SID, "DefaultEngineTTS", "", device) -- restore default
	end
	local googleURL = getVar("GoogleTTSServerURL", "", device, SONOS_SID, true)
	if googleURL == "" then
		googleURL = "https://translate.google.com"
	elseif googleURL == "https://translate.google.com" then
		setVar(SONOS_SID, "GoogleTTSServerURL", "", device) -- restore default
	end
	local serverURL = getVar("OSXTTSServerURL", "", device, SONOS_SID, true)
	local maryURL = getVar("MaryTTSServerURL", "", device, SONOS_SID, true)
	local rvURL = getVar("ResponsiveVoiceTTSServerURL", "", device, SONOS_SID, true)
	if "" == rvURL then
		rvURL = "https://code.responsivevoice.org"
	elseif rvURL:match("^http:") or rvURL == "https://code.responsivevoice.org" then
		rvURL = "https://code.responsivevoice.org"
		setVar(SONOS_SID, "ResponsiveVoiceTTSServerURL", "", device)
	end
	local clientId = getVar("MicrosoftClientId", "", device, SONOS_SID, true)
	local clientSecret = getVar("MicrosoftClientSecret", "", device, SONOS_SID, true)
	local option = getVar("MicrosoftOption", "", device, SONOS_SID, true)
	-- NOTA BENE! TTSBaseURL must resolve to TTSBasePath in runtime! That is, whatever directory
	--            TTSBasePath points to must be the directory accessed via TTSBaseURL.
	TTSBaseURL = getVar("TTSBaseURL", "", device, SONOS_SID, true)
	if ttsrev < 19269 or not TTSBaseURL:match("%/$") then
		setVar(SONOS_SID, "TTSBaseURL", "", device)
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
	TTSBasePath = getVar("TTSBasePath", "", device, SONOS_SID, true)
	if ttsrev < 19269 or not TTSBasePath:match("%/$") then
		setVar(SONOS_SID, "TTSBasePath", "", device)
		TTSBasePath = ""
	end
	if "" == TTSBasePath then
		TTSBasePath = getInstallPath()
		if not isOpenLuup and luup.short_version then
			-- Real Vera 7.30+
			TTSBasePath = "/www/sonos/"
		end
	end
	setVar(SONOS_SID, "_ttsrev", 19269, device)

	tts.setup(lang, engine, googleURL, serverURL, maryURL, rvURL, clientId, clientSecret, option)

	local RV = tts.getEngine("RV")
	if RV then
		local rate = getVar("TTSRate", "", device, SONOS_SID, true)
		if "" == rate then
			rate = "0.5"
		elseif "0.5" == rate then
			setVar(SONOS_SID, "TTSRate", "", device) -- restore default
		end
		local pitch = getVar("TTSPitch", "", device, SONOS_SID, true)
		if "" == pitch then
			pitch = "0.5"
		elseif "0.5" == pitch then
			setVar(SONOS_SID, "TTSPitch", "", device) -- restore default
		end
		RV.pitch = pitch
		RV.rate = rate
	end

	TTSChime = nil
	local installPath = getInstallPath()
	if file_exists( installPath .. "Sonos_chime.mp3" ) then
		if TTSBasePath ~= installPath then
			os.execute( "ln -sf " .. installPath .. "Sonos_chime.mp3 " .. TTSBasePath )
		end
		TTSChime = { URI=TTSBaseURL.."Sonos_chime.mp3" }
		TTSChime.URIMetadata = TTS_METADATA:format( "TTS Chime", "http-get:*:audio/mpeg:*", TTSChime.URI )
		TTSChime.Duration = getVarNumeric( "TTSChimeDuration", 3, device, SONOS_SID )
		TTSChime.TempFile = nil -- flag no delete in endPlayback
	end
	os.remove( installPath .. "Sonos_chime.wav" )
	os.remove( TTSBasePath .. "Sonos_chime.wav" )
end

function updateWithoutProxy(device)
	local dn = tonumber(device) or _G.error "updateWithoutProxy() invalid device: "..tostring(device)
	refreshNow(dn, true, true)
	if not upnp.proxyVersionAtLeast(1) then
		local ts = getVar( "TransportState", "STOPPED", dn, UPNP_AVTRANSPORT_SID )
		local rp,rs = getVar("PollDelays", "15,60", dn):match( '^(%S+)%,%s*(.*)$' )
		rp = tonumber(rp) or 15
		rs = tonumber(rs) or 60
		luup.call_delay("updateWithoutProxy", ( ts == "STOPPED" ) and rs or rp, device)
		debug("Scheduled update for no proxy, state "..tostring(ts))
		return
	end
	debug("Proxy found, skipping poll reschedule")
end

local function getAvailableServices(uuid)
	debug("getAvailableServices: start")
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
				debug("getAvailableServices: " .. string.format('%s => %s', id, name))
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
local function setDeviceIcon( device, icon, model, udn )
	-- Set up local copy of icon from device and static JSON pointing to it
	-- (so icon works both locally and remote)
	local ICONREV = 19295
	local icorev = getVarNumeric("_icorev", 0, device)
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
		log( string.format("Fetching custom device icon from %s to %s%s", icon, installPath, iconFile ) )
		os.execute( "curl -s -o " .. Q( installPath..iconFile ) .. " " .. Q( icon ) )
	end
	if installPath ~= iconPath then
		os.execute( "ln -sf " .. Q(installPath..iconFile) .. " " .. Q(iconPath) )
	end
	-- See if we've already created a custom static JSON for this UDN or model.
	local staticJSONFile
	if udn then
		staticJSONFile = string.format( "D_Sonos1_%s.json", tostring( udn ):lower():gsub( "^uuid:", "" ):gsub( "[^a-z0-9_]", "_" ) )
		if file_exists_LZO( installPath .. staticJSONFile ) then
			log( string.format( "using device-specific UI %s", staticJSONFile ) )
		else
			staticJSONFile = nil
		end
	end
	if not staticJSONFile then
		staticJSONFile = string.format( "D_Sonos1_%s.json", tostring( model or "GENERIC" ):upper():gsub( "[^A-Z0-9_]", "_" ) )
	end
	if icorev < ICONREV or not file_exists_LZO( installPath .. staticJSONFile ) then
		-- Create model-specific version of static JSON
		log("Creating static JSON in "..staticJSONFile)
		local s,f = file_exists( installPath.."D_Sonos1.json", true )
		if not s then
			os.execute( 'pluto-lzo d ' .. Q(installPath .. 'D_Sonos1.json.lzo') .. ' /tmp/D_Sonos1.json.tmp' )
			f = io.open( '/tmp/D_Sonos1.json.tmp', 'r' )
			if not f then
				warning("Failed to open /tmp/D_Sonos1.json.tmp")
				staticJSONFile = nil
			end
		end
		if f then -- explicit, two paths above
			-- Read default static JSON
			s = f:read("*a")
			f:close()
			local json = require "dkjson"
			local d = json.decode( s )
			if not d then _G.error "Can't parse generic static JSON file" end
			-- Modify to new icon in default path
			local ist = iconURL:format( iconFile )
			debug( "Creating static JSON for icon " .. ist )
			d.default_icon = ist
			d.flashicon = nil
			-- d.state_icons = nil
			d._comment = { "AUTOMATICALLY GENERATED -- DO NOT MODIFY THIS FILE (rev " .. ICONREV .. ")" }
			-- Save custom.
			f = io.open( installPath .. staticJSONFile, "w" )
			if not f then
				error( string.format("can't write %s%s", installPath, staticJSONFile), 1)
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
		warning(string.format("device_json currently %s, swapping to %s (and reloading)", cj, staticJSONFile ))
		luup.attr_set( 'device_json', staticJSONFile, device )
		-- rigpapa: by using a delay here, we increase the chances that changes for multiple
		-- players can be captured in one reload, rather than one per.
		luup.call_delay( 'SonosReload', 15, "" )
	end
	setVar( SONOS_SID, "_icorev", ICONREV, device )
end

setup = function(device, init)
	device = tonumber(device)

	local changed = false
	local info

	local newDevice = false
	local newIP
	 if (device == 0) then
		newIP = ip[device]
	else
		newIP = luup.attr_get("ip", device)
	end
	if (newIP ~= ip[device]) then
		newDevice = true
		upnp.resetServices(UUIDs[device])
		upnp.cancelProxySubscriptions(EventSubscriptions)
		UUIDs[device] = ""
		ip[device] = newIP
		changed = setData("ZoneName", "", device, changed)
		changed = setData("SonosID", "", device, changed)
		changed = setData("SonosModelName", "", device, changed)
		changed = setData("SonosModel", "", device, changed)
		changed = setData("SonosOnline", "0", device, changed)
	end

	if (ip[device] == nil or ip[device] == "") then
		setData("ZoneName", "", device, changed)
		setData("SonosID", "", device, changed)
		setData("SonosModelName", "", device, changed)
		setData("SonosModel", "", device, changed)
		setData("ProxyUsed", "", device, changed)
		deviceIsOffline(device)
		return
	end

	local descrURL = string.format(descriptionURL, ip[device], port)
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
	if (status == false) then
		deviceIsOffline(device)
		return
	end

	local newOnline = deviceIsOnline(device)

	local uuid = values.UDN:match("uuid:(.+)") or ""
	UUIDs[device] = uuid
	ip[uuid] = ip[device]
	if (dataTable[uuid] == nil) then
		dataTable[uuid] = {}
	end
	local roomName = values.roomName
	if (roomName ~= nil) then
		roomName = upnp.decode(roomName)
	end
	changed = setData("ZoneName", roomName or "", device, changed)
	changed = setData("SonosID", uuid, device, changed)
	local modelName = values.modelName
	if (modelName ~= nil) then
		modelName = upnp.decode(modelName)
	end
	changed = setData("SonosModelName", modelName or "", device, changed)
	changed = setData("SonosModelNumber", values.modelNumber or "", device, changed)
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
	elseif values.modelNumber == "S12" then
		-- Newer hardware revision of Play 1
		model = 6 -- 2019-07-05 rigpapa; from @cranb https://community.getvera.com/t/version-1-4-3-development/209171/11
	end
	changed = setData("SonosModel", string.format("%d", model), device, changed)

	log( string.format("#%s at %s is %q, %s (%s) %s",
		tostring( device ),
		tostring( ip[device] ),
		tostring( modelName ),
		tostring( values.modelNumber ), model,
		tostring( values.UDN )
		)
	)

	if icon then
		iconURL = icon
		-- Use pcall so any issue setting up icon does not interfere with initialization and operation
		pcall( setDeviceIcon, device, icon, values.modelNumber, values.UDN )
	else
		iconURL = PLUGIN_ICON
	end

	if (device ~= 0 and (init or newDevice or newOnline)) then
		upnp.subscribeToEvents(device, VERA_IP, EventSubscriptions, SONOS_SID, uuid)
	end

	if upnp.proxyVersionAtLeast(1) then
		changed = setData("ProxyUsed", "proxy is in use", device, changed)
		BROWSE_TIMEOUT = 30
	else
		changed = setData("ProxyUsed", "proxy is not in use", device, changed)
		BROWSE_TIMEOUT = 5
	end

	if (init or newDevice or newOnline) then
		sonosServices = getAvailableServices(uuid)
		metaDataKeys[uuid] = loadServicesMetaDataKeys(device)
	end

	if (init or newDevice or newOnline or not upnp.proxyVersionAtLeast(1) ) then
		-- Sonos playlists
		info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "SQ:", false, "dc:title", parseSavedQueues, BROWSE_TIMEOUT)
		changed = setData("SavedQueues", info, device, changed)

		-- Favorites radio stations
		info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "R:0/0", false, "dc:title", parseIdTitle, BROWSE_TIMEOUT)
		changed = setData("FavoritesRadios", info, device, changed)

		-- Sonos favorites
		info = upnp.browseContent(uuid, UPNP_MR_CONTENT_DIRECTORY_SERVICE, "FV:2", false, "dc:title", parseIdTitle, BROWSE_TIMEOUT)
		changed = setData("Favorites", info, device, changed)
	end

	if changed then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), device)
	end

	if (newDevice or newOnline) then
		refreshNow(device, true, true)
	end
end

local function getCheckStateRate(device)
	return getVarNumeric("CheckStateRate", 0, device) * 60
end

function checkDeviceState(data)
	debug("checkDeviceState " .. data)
	local cpt, device = data:match("(%d+):(%d+)")
	if (cpt ~= nil and device ~= nil) then
		cpt = tonumber(cpt)
		if (cpt == nil or cpt ~= idConfRefresh) then
			return
		end
		device = tonumber(device)
		local rate = getCheckStateRate(device)
		if rate > 0 then
			luup.call_delay("checkDeviceState", rate, idConfRefresh .. ":" .. device)
			setup(device, false)
		end
	end
end

local function setCheckStateRate(device, rate)
	debug("setCheckStateRate rate=" .. (rate or "nil"))
	if tonumber(rate) == nil then rate = 0 end
	setVar(SONOS_SID, "CheckStateRate", rate, device)

	idConfRefresh = idConfRefresh + 1

	checkDeviceState(idConfRefresh .. ":" .. device)
end

local function handleRenderingChange(device, event)
	debug("handleRenderingChange for device " .. device .. " value " .. event)
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
				changed = setData(token, upnp.decode(attrTable.val), device, changed)
			end
		end
	end
	if changed then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), device)
	end
end

local function handleAVTransportChange(device, uuid, event)
	debug("handleAVTransportChange for device " .. device .. " UUID " .. uuid .. " value " .. event)
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
				changed = setData(token, upnp.decode(attrTable.val), device, changed)
			end
		end

		currentUri = dataTable[uuid].AVTransportURI
		currentUriMetaData = dataTable[uuid].AVTransportURIMetaData
		trackUri = dataTable[uuid].CurrentTrackURI
		trackUriMetaData = dataTable[uuid].CurrentTrackMetaData
		service, title, statusString, title2, artist, album, details, albumArt =
			extractDataFromMetaData(device, currentUri, currentUriMetaData, trackUri, trackUriMetaData)
		changed = setData("CurrentService", service, device, changed)
		changed = setData("CurrentRadio", title, device, changed)
		changed = setData("CurrentStatus", statusString, device, changed)
		changed = setData("CurrentTitle", title2, device, changed)
		changed = setData("CurrentArtist", artist, device, changed)
		changed = setData("CurrentAlbum", album, device, changed)
		changed = setData("CurrentDetails", details, device, changed)
		changed = setData("CurrentAlbumArt", albumArt, device, changed)

		if not found then
			local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
			if AVTransport ~= nil then
				local _, tmp2 = AVTransport.GetPositionInfo({InstanceID="0"})
				changed = setData("RelativeTimePosition", upnp.extractElement("RelTime", tmp2, "NOT_IMPLEMENTED"), device, changed)
			end
		end

		if found2 then
			_, title, artist, album, details, albumArt, desc = -- luacheck: ignore 311
				getSimpleDIDLStatus(dataTable[uuid]["r:EnqueuedTransportURIMetaData"])
			_, serviceId = getServiceFromURI(currentUri, trackUri)
			updateServicesMetaDataKeys(device, serviceId, desc)
		end
	end
	if changed then
		setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), device)
	end
end

local function handleContentDirectoryChange(device, uuid, id)
	debug("handleContentDirectoryChange for device " .. device .. " UUID " .. uuid .. " value " .. id)
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
	debug("Processing UPnP Event Proxy subscriptions: " .. info)
	upnp.processProxySubscriptions()
end

-- N.B. called via call_delay from L_SonosUPnP
function renewSubscriptions(data)
	local device, uuid = data:match("(%d+):(.*)")
	if (device ~= nil and uuid ~= nil) then
		device = tonumber(device)
		debug("Renewal of all event subscriptions for device " .. device)
		if (uuid ~= UUIDs[device]) then
			debug("Renewal ignored for uuid " .. uuid)
		elseif (upnp.subscribeToEvents(device, VERA_IP, EventSubscriptions, SONOS_SID, UUIDs[device]) == false) then
			setup(device, true)
		end
	end
end

-- N.B. called via call_delay from L_SonosUPnP
function cancelProxySubscription(sid)
	upnp.cancelProxySubscription(sid)
end

local function setDebugLogs(device, enable)
	debug("setDebugLogs " .. (enable or "nil"))

	if ((enable == "true") or (enable == "yes"))
	then
		enable = "1"
	elseif ((enable == "false") or (enable == "no"))
	then
		enable = "0"
	end
	if ((enable ~= "0") and (enable ~= "1"))
	then
		task("SetDebugLogs: invalid argument", TASK_ERROR)
		return
	end

	luup.variable_set(SONOS_SID, "DebugLogs", enable, device)
	if (enable == "1")
	then
		DEBUG_MODE = true
	else
		DEBUG_MODE = false
	end
end

local function setReadQueueContent(device, enable)
	debug("setReadQueueContent " .. (enable or "nil"))

	if ((enable == "true") or (enable == "yes"))
	then
		enable = "1"
	elseif ((enable == "false") or (enable == "no"))
	then
		enable = "0"
	end
	if ((enable ~= "0") and (enable ~= "1"))
	then
		task("SetReadQueueContent: invalid argument", TASK_ERROR)
		return
	end

	luup.variable_set(SONOS_SID, "FetchQueue", enable, device)
	if (enable == "1")
	then
		fetchQueue = true
	else
		fetchQueue = false
	end
	handleContentDirectoryChange(device, UUIDs[device], "Q:0,")
end

function SonosReload()
	warning( 'Requesting luup reload...' )
	luup.reload()
end

-- Check that the proxy is running.
function checkProxy(data) -- luacheck: ignore 212
	local proxy = false
	local version = upnp.getProxyApiVersion()
	if version then
		log("UPnP Event Proxy identified - API version " .. version)
		proxy = true
	else
		warning("UPnP Event Proxy plugin could not be contacted; polling for status will be used. This is inefficient; please consider installing the plugin from the marketplace.")
	end

	if ( not proxy ) then
		upnp.unuseProxy()
	end

	luup.call_delay("checkProxy", 300)
end

function deferredStartup(device)
	debug("deferredStartup: start " .. device)
	device = tonumber(device)

	for k,v in pairs(ip) do
		luup.log("deferredStartup sees ip["..k.."]="..v, 1)
	end

	-- Check that the proxy is running.
	checkProxy(device)

	-- the next line has to be uncommented to force the old mode without the UPnP event proxy
	-- upnp.unuseProxy()

	if (luup.devices[device].device_type == SONOS_DEVICE_TYPE) then
		UUIDs[device] = ""
		ip[device] = luup.attr_get("ip", device)

		setupTTSSettings(device)

		idConfRefresh = 0
		local rate = getCheckStateRate(device)
		if (rate > 0) then
			luup.call_delay("checkDeviceState", rate, idConfRefresh .. ":" .. device)
		end
		setup(device, true)
		updateWithoutProxy(device)
	end
end

function startup( lul_device )
	log("version " .. PLUGIN_VERSION .. " starting up #" .. lul_device .. " ("
		.. luup.devices[lul_device].description .. ")")

	isOpenLuup = luup.openLuup ~= nil

	local debugLogs = getVarNumeric("DebugLogs", 0, lul_device)
	if debugLogs ~= 0 then
		DEBUG_MODE = true
		if upnp and math.floor( debugLogs / 2 ) % 2 == 1 then upnp.DEBUG_MODE = true end
		if tts and math.floor( debugLogs / 4 ) % 2 == 1 then tts.DEBUG_MODE = true end
	end

	-- Check for version 2.0 installed. If we're running here and we see 2.0 installed, it means this
	-- device is about to be upgraded as a 2.0 child. Don't do this startup. The 2.0 system device will
	-- adopt this device (as child) and remove its 1.x implementation.
	if file_exists( getInstallPath() .. "D_SonosSystem1.xml.lzo" ) or
		file_exists( getInstallPath() .. "D_SonosSystem1.xml" ) then
		-- Find the 2.0 SonosSystem device and lowest numbered 1.x zone
		local minzone = lul_device
		local sysdev = false
		for k,v in pairs( luup.devices ) do
			if v.device_type == "urn:schemas-micasaverde-com:device:SonosSystem:1" then
				sysdev = k -- found system device
				break
			elseif v.device_type == "urn:schemas-micasaverde-com:device:Sonos:1" and v.device_num_parent == 0 then
				if k < minzone then minzone = k end
			end
		end
		-- If 2.0 system device does not exist, and this is the lowest numbered 1.x device, create
		-- the 2.0 system device and reload. For sanity, only one attempt is made at this.
		log(string.format("Lowest numbered Sonos 1.x device is %s; SonosSystem device is %s",
			tostring(minzone), tostring(sysdev)))
		if not sysdev and lul_device == minzone and getVarNumeric( "UpgradeAttempted", 0, lul_device, SONOS_SID ) == 0 then
			setVar( SONOS_SID, "UpgradeAttempted", os.time(), lul_device )
			log("Upgrade prep 2.0, didn't find SonosSystem device, creating and reloading...")
			luup.call_action( "urn:micasaverde-com:serviceId:HomeAutomationGateway1", "CreateDevice", 
				{ UpnpDevFilename="D_SonosSystem1.xml", UpnpImplFilename="I_SonosSystem1.xml",
				  Description="Sonos Plugin", Reload="1" }, 0 )
			luup.call_delay( 'SonosReload', 30, "" ) -- insurance
		end
		log(string.format("Not starting Sonos device #%d in 1.x mode, detected plugin 2.0 installed", lul_device))
		setData("CurrentStatus", "Pending 2.0 upgrade...", lul_device, false)
		return true
	end

	if not isOpenLuup and luup.short_version then
		-- Real Vera 7.30+
		os.execute("mkdir -p /www/sonos/")
	end
	pcall( fixLegacyIcons )

	debug("UPnP module is "..tostring(upnp.VERSION))
	if ( upnp.VERSION or 0 ) < MIN_UPNP_VERSION then
		error "The L_SonosUPNP module installed is not compatible with this version of the plugin core."
		return false, "Invalid installation", MSG_CLASS
	end
	if not tts then
		log("TTS module is not installed (it's optional)")
	else
		debug("TTS module is "..tostring(tts.VERSION))
		if ( tts.VERSION or 0 ) < MIN_TTS_VERSION then
			warning "The L_SonosTTS module installed may not be compatible with this version of the plugin core."
		end
	end

	setData( "PluginVersion", PLUGIN_VERSION, lul_device, false )
	initData( "PollDelays", "15,60", lul_device )

	local enabled = initData( "Enabled", "1", lul_device )
	if "0" == enabled then
		warning(luup.devices[lul_device].description.." (#"..lul_device..") disabled by configuration; startup aborting.")
		deviceIsOffline( lul_device )
		return true, "Offline", MSG_CLASS
	end

	if (luup.variable_get(SONOS_SID, "DiscoveryResult", lul_device) == nil
			or luup.variable_get(SONOS_SID, "DiscoveryResult", lul_device) == "scanning") then
		luup.variable_set(SONOS_SID, "DiscoveryResult", "", lul_device)
	end

	local routerIp = getVar("RouterIp", "", lul_device, SONOS_SID, true)
	local routerPort = getVar("RouterPort", "", lul_device, SONOS_SID, true)

	initVar("CheckStateRate", "", lul_device, SONOS_SID)

	local fetch = getVarNumeric("FetchQueue", -1, lul_device)
	if fetch < 0 then
		setVar(SONOS_SID, "FetchQueue", "1", lul_device)
		fetch = 1
	end
	if fetch == 0 then
		fetchQueue = false
	end

	--
	-- Acquire the IP Address of Vera itself, needed for the Say method later on.
	-- Note: We're assuming Vera is connected via it's WAN Port to the Sonos devices
	--
	VERA_LOCAL_IP = getVar("LocalIP", "", lul_device, SONOS_SID, true)
	if VERA_LOCAL_IP == "" then
		local stdout = io.popen("GetNetworkState.sh ip_wan")
		VERA_LOCAL_IP = stdout:read("*a")
		stdout:close()
	end
	debug("sonosStartup: Vera IP Address=" .. VERA_LOCAL_IP)
	if VERA_LOCAL_IP == "" then
		error("Unable to establish local IP address of Vera/openLuup system. Please set 'LocalIP'")
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

	ip, playbackCxt, sayPlayback, UUIDs, metaDataKeys, dataTable = upnp.initialize(log, warning, error)

	if tts then
		tts.initialize(log, warning, error)
	end

	port = 1400
	descriptionURL = "http://%s:%s/xml/device_description.xml"
	iconURL = PLUGIN_ICON

	if (upnp.isDiscoveryPatchInstalled(VERA_LOCAL_IP)) then
		luup.variable_set(SONOS_SID, "DiscoveryPatchInstalled", "1", lul_device)
	else
		luup.variable_set(SONOS_SID, "DiscoveryPatchInstalled", "0", lul_device)
	end

	luup.call_delay("deferredStartup", 1, lul_device)

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
	local duration = tonumber(defaultValue(parameters, "Duration", "0")) or 0
	local sameVolume = false
	if (parameters.SameVolumeForAll == "true"
		or parameters.SameVolumeForAll == "TRUE"
		or parameters.SameVolumeForAll == "1") then
		sameVolume = true
	end

	if (uri or "") == "" then
		if saveAndRestore then
			endSayAlert( device )
		end
		return
	end

	local targets = {}
	local newGroup = true
	local localUUID = UUIDs[device]

	-- Figure out where we're going to speak/alert
	if zones:upper() == "CURRENT" then
		-- If we're using the CURRENT ZoneGroup, then we don't need to restructure groups, just
		-- announce to the coordinator of the group (so set that up if needed). In all other cases,
		-- we restructure to a temporary group, for which the current `device` is the coordinator.
		local gr = zoneInfo.groups[zoneInfo.zones[localUUID].Group] or {}
		targets = { [gr.Coordinator]=true }
		newGroup = false
		if gr.Coordinator ~= localUUID then
			debug("sayOrAlert() CURRENT zone group, switching to coordinator "..gr.Coordinator)
			localUUID = gr.Coordinator
			device = controlAnotherZone( localUUID, device )
			if (device or 0) == 0 then
				warning("(tts/alert) cannot control "..localUUID..", not found or not ready")
				return
			end
		end
	elseif zones:upper() == "ALL" then
		local _, lt = getAllUUIDs() -- returns modification-safe array
		targets = map( lt ) -- array of UUIDs to table with UUIDs as keys
	else
		local uuid
		for id in devices:gmatch("[^,]+") do
			local nid = tonumber(id)
			if not nid then
				warning("Say/Alert action GroupDevices device "..tostring(id).." not a valid device number (ignored)")
			elseif not UUIDs[nid] then
				warning("Say/Alert action GroupDevices device "..tostring(id).." not a known Sonos device (ignored)")
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
			if (uuid or "") ~= "" then
				targets[uuid] = true
			end
		end
	end
	debug("sayOrAlert() targets are "..dump(targets))

	if saveAndRestore and not sayPlayback[device] then
		-- Save context for all affected members. For starters, this is all target members.
		targets[localUUID] = true -- we always save context for the controlling device
		local affected = clone( targets )
		debug("sayOrAlert() affected is "..dump(affected))

		-- Now, find any targets that happen to be coordinators of groups. All members are affected
		-- by removing/changing the coordinator when the temporary alert group is created.
		for uuid in pairs( targets ) do
			local gr = getZoneGroup( uuid ) or {}
			debug("sayOrAlert() zone group for target "..uuid.." is "..dump(gr))
			if gr.Coordinator == uuid and #gr.members > 1 then
				-- Target is a group coordinator; add all group members to affected list
				debug("sayOrAlert() "..uuid.." is coordinator, adding group members to affected list")
				affected = map( gr.members, nil, affected )
			end
		end

		-- Save state for all affected members
		debug("sayOrAlert() final affected list is "..dump(affected))
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
					debug("sayOrAlert() removing group association for affected zone " .. uuid)
					AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID=instanceId})
				end
			end
		end
	end

	playURI(device, instanceId, uri, "1", volume, newGroup and keys(targets) or nil, sameVolume, nil, newGroup, true)

	if saveAndRestore and (duration or 0) > 0 then
		debug("sayOrAlert() delaying for duration "..duration)
		luup.call_delay("endSayAlert", duration, device)
	end

	refreshNow(device, false, false)
end

local function queueAlert(device, settings)
	debug("TTS queueAlert for device " .. device)
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
	if sayQueue[device] and #sayQueue[device] > 0 then
		local settings = sayQueue[device][1]
		debug("endTTSPlayback() finished "..settings.URI)
		if settings.TempFile then
			-- Remove temp file
			os.execute(string.format("rm -f -- %s", Q(settings.TempFile)))
		end
		table.remove(sayQueue[device], 1)
		debug("endTTSPlayback() queue contains "..#sayQueue[device].." more")
		if #sayQueue[device] > 0 then
			sayOrAlert(device, sayQueue[device][1], true)
			return false
		end
	end
	debug("endTTSPlayback() queue now empty")
	sayQueue[device] = nil
	return true -- finished
end

-- Callback for end of alert/Say.
endSayAlert = function(device)
	debug("TTS endSayAlert for device " .. device)
	if not tts then return end
	device = tonumber(device) or error("Invalid parameter/device number for endSayAlert")
	if endTTSPlayback(device) and sayPlayback[device] then
		local playCxt = sayPlayback[device]
		if playCxt.newGroup then
			-- Temporary group was used; reset group structure.
			-- First remove all to-be-restored devices from their current groups.
			debug("endSayAlert() restoring group structure after temporary group")
			for uuid in pairs( playCxt.context or {} ) do
				debug("endSayAlert() clearing group for " .. uuid)
				local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
				if AVTransport ~= nil then
					AVTransport.Stop({InstanceID="0"})
					AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID="0"})
				end
			end
			debug("endSayAlert() restoring group structure")
			for uuid,cxt in pairs( playCxt.context or {} ) do
				debug("endSayAlert() affected "..uuid.." context "..dump(cxt))
				if cxt.GroupCoordinator ~= uuid then
					debug("endSayAlert() restoring member "..uuid.." to "..cxt.GroupCoordinator)
					-- Add this uuid to its prior GroupCoordinator
					local device2 = controlAnotherZone( uuid, device )
					if device2 then
						playURI(device2, "0", "x-rincon:" .. cxt.GroupCoordinator, "1", nil, nil, false, nil, false, false)
					end
				else
					debug("endSayAlert() "..uuid.." is its own group coordinator")
				end
			end
		end

		debug("endSayAlert() restoring saved playback contexts")
		restorePlaybackContexts(device, playCxt)
		sayPlayback[device] = nil
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
		warning("(tts) clearing cache " .. tostring(cpath))
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
			log("(tts) speaking phrase from cache: " .. tostring(settings.URI))
			return settings
		end
	end
	if engobj then
		-- Convert text to speech using specified engine
		local file = string.format( "Say.%s.%s", tostring(device), engobj.fileType or "mp3" )
		local destFile = TTSBasePath .. file
		settings.Duration = tts.ConvertTTS(text, destFile, settings.Language, settings.Engine, {})
		if (settings.Duration or 0) == 0 then
			warning("(tts) "..tostring(engobj.title).." produced no audio")
			return
		end
		settings.URI = TTSBaseURL .. file
		settings.TempFile = destFile
		settings.URIMetadata = TTS_METADATA:format(engobj.title, engobj.protocol,
			settings.URI)
		log("(tts) "..tostring(engobj.title).." created "..tostring(settings.URI))
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
				warning("(tts) cache failed to copy "..Q( destFile ).." to "..Q( cpath..fmeta.nextfile..ft ))
			else
				fmeta.strings[text] = { duration=settings.Duration, url=curl .. fmeta.nextfile .. ft, created=os.time() }
				fm = io.open( cpath .. "ttsmeta.json", "w" )
				if fm then
					local json = require "dkjson"
					fmeta.nextfile = fmeta.nextfile + 1
					fm:write(json.encode(fmeta))
					fm:close()
					debug("(tts) cached " .. destFile .. " as " .. fmeta.strings[text].url)
				else
					warning("(ttscache) can't write cache meta in " .. cpath)
				end
			end
		end
	else
		warning("No TTS engine implementation for "..tostring(settings.Engine))
		return nil
	end
	return settings
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:micasaverde-com:serviceId:Sonos1

--]]

function actionSonosSay( lul_device, lul_settings )
	log("Say action on device " .. tostring(lul_device) .. " text " .. tostring(lul_settings.Text))
	if not tts then
		warning "The Sonos TTS module is not installed or could not be loaded."
		return
	end
	if ( tts.VERSION or 0 ) < MIN_TTS_VERSION then
		warning "The L_SonosTTS module installed may not be compatible with this version of the plugin core."
	end
	if ( luup.attr_get( 'UnsafeLua', 0 ) or "0" ) ~= "1" and not isOpenLuup then
		warning "The TTS module requires that 'Enable Unsafe Lua' (under 'Users & Account Info > Security') be enabled in your controller settings."
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
	luup.variable_set(SONOS_SID, "DefaultLanguageTTS"				, lul_settings.DefaultLanguage or "", lul_device)
	luup.variable_set(SONOS_SID, "DefaultEngineTTS"					, lul_settings.DefaultEngine or "", lul_device)
	luup.variable_set(SONOS_SID, "OSXTTSServerURL"					, url.unescape(lul_settings.OSXTTSServerURL				or ""), lul_device)
	luup.variable_set(SONOS_SID, "GoogleTTSServerURL"				, url.unescape(lul_settings.GoogleTTSServerURL			or ""), lul_device)
	luup.variable_set(SONOS_SID, "MaryTTSServerURL"					, url.unescape(lul_settings.MaryTTSServerURL			or ""), lul_device)
	luup.variable_set(SONOS_SID, "MicrosoftClientId"				, url.unescape(lul_settings.MicrosoftClientId			or ""), lul_device)
	luup.variable_set(SONOS_SID, "MicrosoftClientSecret"			, url.unescape(lul_settings.MicrosoftClientSecret		or ""), lul_device)
	luup.variable_set(SONOS_SID, "MicrosoftOption"					, url.unescape(lul_settings.MicrosoftOption				or ""), lul_device)
	luup.variable_set(SONOS_SID, "ResponsiveVoiceTTSServerURL"		, url.unescape(lul_settings.ResponsiveVoiceTTSServerURL	or ""), lul_device)
	luup.variable_set(SONOS_SID, "TTSRate"							, url.unescape(lul_settings.Rate						or ""), lul_device)
	luup.variable_set(SONOS_SID, "TTSPitch"							, url.unescape(lul_settings.Pitch						or ""), lul_device)
	setupTTSSettings(lul_device)
	os.execute( "rm -rf -- " .. Q(TTSBasePath .. "ttscache") )
end

function actionSonosResetTTS( lul_device )
	luup.variable_set(SONOS_SID, "DefaultLanguageTTS"			, "", lul_device)
	luup.variable_set(SONOS_SID, "DefaultEngineTTS"				, "", lul_device)
	luup.variable_set(SONOS_SID, "OSXTTSServerURL"				, "", lul_device)
	luup.variable_set(SONOS_SID, "GoogleTTSServerURL"			, "", lul_device)
	luup.variable_set(SONOS_SID, "MaryTTSServerURL"				, "", lul_device)
	luup.variable_set(SONOS_SID, "MicrosoftClientId"			, "", lul_device)
	luup.variable_set(SONOS_SID, "MicrosoftClientSecret"		, "", lul_device)
	luup.variable_set(SONOS_SID, "MicrosoftOption"				, "", lul_device)
	luup.variable_set(SONOS_SID, "ResponsiveVoiceTTSServerURL"	, "", lul_device)
	luup.variable_set(SONOS_SID, "TTSRate"						, "", lul_device)
	luup.variable_set(SONOS_SID, "TTSPitch"						, "", lul_device)
	luup.variable_set(SONOS_SID, "TTSBasePath"					, "", lul_device)
	luup.variable_set(SONOS_SID, "TTSBaseURL"					, "", lul_device)
	setupTTSSettings(lul_device)
end

function actionSonosSetURIToPlay( lul_device, lul_settings )
	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local uri = defaultValue(lul_settings, "URIToPlay", "")

	playURI(lul_device, instanceId, uri, nil, nil, nil, false, nil, false, true)

	refreshNow(lul_device, false, true)

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
	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local uri = defaultValue(lul_settings, "URIToPlay", "")
	local volume = defaultValue(lul_settings, "Volume", nil)
	local speed = defaultValue(lul_settings, "Speed", "1")

	playURI(lul_device, instanceId, uri, speed, volume, nil, false, nil, false, true)

	refreshNow(lul_device, false, true)

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
	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local uri = defaultValue(lul_settings, "URIToEnqueue", "")
	local enqueueMode = defaultValue(lul_settings, "EnqueueMode", "ENQUEUE_AND_PLAY")

	playURI(lul_device, instanceId, uri, "1", nil, nil, false, enqueueMode, false, true)

	refreshNow(lul_device, false, true)
end

function actionSonosAlert( lul_device, lul_settings )
	log("Alert action on device " .. tostring(lul_device) .. " URI " .. tostring(lul_settings.URI) ..
		" duration " .. tostring(lul_settings.Duration))
	local duration = tonumber(defaultValue(lul_settings, "Duration", "0")) or 0
	if duration > 0 then
		-- Sound already defined
		queueAlert(lul_device, lul_settings)
	else
		log("Alert playing without save/restore, no Duration supplies")
		sayOrAlert(lul_device, lul_settings, false)
	end
end

function actionSonosPauseAll( lul_device, lul_settings ) -- luacheck: ignore 212
	pauseAll(lul_device)
end

function actionSonosJoinGroup( lul_device, lul_settings )
	local zone = defaultValue(lul_settings, "Zone", "")
	joinGroup(lul_device, zone)
end

function actionSonoLeaveGroup( lul_device, lul_settings ) -- luacheck: ignore 212
	leaveGroup(lul_device)
end

function actionSonosUpdateGroupMembers( lul_device, lul_settings )
	local zones = url.unescape(defaultValue(lul_settings, "Zones", ""))
	updateGroupMembers(lul_device, zones)
end

function actionSonosSavePlaybackContext( lul_device, lul_settings )
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
				warning("SavePlaybackContext action GroupDevices element '"..tostring(id).."' invalid or unknown device")
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
	restorePlaybackContexts(lul_device, playbackCxt[lul_device])
	return 4,0
end

function actionSonosStartDiscovery( lul_device, lul_settings ) -- luacheck: ignore 212
	setVariableValue(SONOS_SID, "DiscoveryResult", "scanning", lul_device)
	local xml = upnp.scanUPnPDevices("urn:schemas-upnp-org:device:ZonePlayer:1", { "modelName", "friendlyName", "roomName" })
	setVariableValue(SONOS_SID, "DiscoveryResult", xml, lul_device)
	return 4,0
end

function actionSonosSelectDevice( lul_device, lul_settings )
	local newDescrURL = url.unescape( lul_settings.URL or "" )
	local newIP, newPort = newDescrURL:match("http://([%d%.]-):(%d+)/.-")
	if (newIP ~= nil and newPort ~= nil) then
		luup.attr_set("ip", newIP, lul_device)
		luup.attr_set("mac", "", lul_device)
		setup(lul_device, false)
	end
end

function actionSonosSearchAndSelect( lul_device, lul_settings )
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
	setDebugLogs(lul_device, lul_settings.enable)
end

function actionSonosSetReadQueueContent( lul_device, lul_settings )
	setReadQueueContent(lul_device, lul_settings.enable)
end

function actionSonosInstallDiscoveryPatch( lul_device, lul_settings ) -- luacheck: ignore 212
	local reload = false
	if upnp.installDiscoveryPatch(VERA_LOCAL_IP) then
		reload = true
		log("Discovery patch now installed")
	else
		log("Discovery patch installation failed")
	end
	luup.variable_set(SONOS_SID, "DiscoveryPatchInstalled",
		upnp.isDiscoveryPatchInstalled(VERA_LOCAL_IP) and "1" or "0", lul_device)
	if reload then
		luup.call_delay("SonosReload", 2, "")
	end
end

function actionSonosUninstallDiscoveryPatch( lul_device, lul_settings ) -- luacheck: ignore 212
	local reload = false
	if upnp.uninstallDiscoveryPatch(VERA_LOCAL_IP) then
		reload = true
		log("Discovery patch now uninstalled")
	else
		log("Discovery patch uninstallation failed")
	end
	luup.variable_set(SONOS_SID, "DiscoveryPatchInstalled",
		upnp.isDiscoveryPatchInstalled(VERA_LOCAL_IP) and "1" or "0", lul_device)
	if reload then
		luup.call_delay("SonosReload", 2, "")
	end
end

function actionSonosNotifyRenderingChange( lul_device, lul_settings )
	if (upnp.isValidNotification("NotifyRenderingChange", lul_settings.sid, EventSubscriptions)) then
		handleRenderingChange(lul_device, lul_settings.LastChange or "")
		return 4,0
	end
	return 2,0
end

function actionSonosNotifyAVTransportChange( lul_device, lul_settings )
	if (upnp.isValidNotification("NotifyAVTransportChange", lul_settings.sid, EventSubscriptions)) then
		handleAVTransportChange(lul_device, UUIDs[lul_device], lul_settings.LastChange or "")
		return 4,0
	end
	return 2,0
end

function actionSonosNotifyMusicServicesChange( lul_device, lul_settings ) -- luacheck: ignore 212
	if (upnp.isValidNotification("NotifyMusicServicesChange", lul_settings.sid, EventSubscriptions)) then
		-- log("NotifyMusicServicesChange for device " .. lul_device .. " SID " .. lul_settings.sid .. " with value " .. (lul_settings.LastChange or "nil"))
		return 4,0
	end
	return 2,0
end

function actionSonosNotifyZoneGroupTopologyChange( lul_device, lul_settings )
	if (upnp.isValidNotification("NotifyZoneGroupTopologyChange", lul_settings.sid, EventSubscriptions)) then
		groupsState = lul_settings.ZoneGroupState or "<ZoneGroupState/>"

		local changed = setData("ZoneGroupState", groupsState, lul_device, false)
		if changed or not zoneInfo then
			updateZoneInfo( lul_device )
		end

		local members, coordinator = getGroupInfos( UUIDs[lul_device] )
		changed = setData("ZonePlayerUUIDsInGroup", members, lul_device, changed)
		changed = setData("GroupCoordinator", coordinator, lul_device, changed)

		if changed then
			setVariableValue(HADEVICE_SID, "LastUpdate", os.time(), lul_device)
		end
		return 4,0
	end
	return 2,0
end

function actionSonosNotifyContentDirectoryChange( lul_device, lul_settings )
	if (upnp.isValidNotification("NotifyContentDirectoryChange", lul_settings.sid, EventSubscriptions)) then
		handleContentDirectoryChange(lul_device, UUIDs[lul_device], lul_settings.ContainerUpdateIDs or "")
		return 4,0
	end
	return 2,0
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:micasaverde-com:serviceId:Volume1

--]]

function actionVolumeMute( lul_device, lul_settings )
	-- Toggle Mute
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local channel = defaultValue(lul_settings, "Channel", "Master")
	local isMuted = getVarNumeric("Mute", 0, lul_device, UPNP_RENDERING_CONTROL_SID, true)
	local desiredMute = 1 - isMuted

	Rendering.SetMute(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "DesiredMute=" .. desiredMute}})

	refreshMuteNow(lul_device)
end

function actionVolumeUp( lul_device, lul_settings )
	-- Volume up
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local channel = defaultValue(lul_settings, "Channel", "Master")

	Rendering.SetRelativeVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "Adjustment=3"}})

	refreshVolumeNow(lul_device)
end

function actionVolumeDown( lul_device, lul_settings )
	-- Volume down
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local channel = defaultValue(lul_settings, "Channel", "Master")

	Rendering.SetRelativeVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "Adjustment=-3"}})

	refreshVolumeNow(lul_device)
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:micasaverde-com:serviceId:MediaNavigation1

--]]

function actionMediaNavigationSkipDown( lul_device, lul_settings )
	local device, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	if (device ~= 0) then
		refreshNow(device, force, false)
	end
end

function actionMediaNavigationSkipUp( lul_device, lul_settings )
	local device, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Previous({InstanceID=instanceId})

	if (device ~= 0) then
		refreshNow(device, false, false)
	end
end

--[[

	IMPLEMENTATIONS FOR ACTIONS IN urn:upnp-org:serviceId:AVTransport

--]]

function actionAVTransportPlayMedia( lul_device, lul_settings )
	local device, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	if (device ~= 0) then
		refreshNow(device, force, false)
	end
end

function actionAVTransportSeek( lul_device, lul_settings )
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local device, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	if (device ~= 0) then
		refreshNow(device, force, false)
	end
end

function actionAVTransportStop( lul_device, lul_settings )
	local device, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Stop({InstanceID=instanceId})

	if (device ~= 0) then
		refreshNow(device, false, false)
	end
end

function actionAVTransportNext( lul_device, lul_settings )
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Next({InstanceID=instanceId})
end

function actionAVTransportPrevious( lul_device, lul_settings )
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.Previous({InstanceID=instanceId})
end

function actionAVTransportNextSection( lul_device, lul_settings )
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.NextSection({InstanceID=instanceId})
end

function actionAVTransportPreviousSection( lul_device, lul_settings )
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.PreviousSection({InstanceID=instanceId})
end

function actionAVTransportNextProgrammedRadioTracks( lul_device, lul_settings )
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.NextProgrammedRadioTracks({InstanceID=instanceId})
end

function actionAVTransportGetPositionInfo( lul_device, lul_settings )
	local device, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	local _, tmp = AVTransport.GetPositionInfo({InstanceID=instanceId})
	setData("RelativeTimePosition", upnp.extractElement("RelTime", tmp, "NOT_IMPLEMENTED"), device, false)
end

function actionAVTransportSetPlayMode( lul_device, lul_settings )
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local currentURI = defaultValue(lul_settings, "CurrentURI", "")
	local currentURIMetaData = defaultValue(lul_settings, "CurrentURIMetaData", "")

	AVTransport.SetAVTransportURI(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"CurrentURI=" .. currentURI,
						"CurrentURIMetaData=" .. currentURIMetaData}})
end

function actionAVTransportSetNextURI( lul_device, lul_settings )
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.RemoveTrackFromQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"ObjectID=" .. lul_settings.ObjectID,
						"UpdateID=" .. lul_settings.UpdateID}})
end

function actionAVTransportRemoveTrackRangeFromQueue( lul_device, lul_settings )
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.RemoveAllTracksFromQueue({InstanceID=instanceId})
end

function actionAVTransportSaveQueue( lul_device, lul_settings )
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.SaveQueue(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"Title=" .. lul_settings.Title,
						"ObjectID=" .. lul_settings.ObjectID}})
end

function actionAVTransportBackupQueue( lul_device, lul_settings )
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.BackupQueue({InstanceID=instanceId})
end

function actionAVTransportChangeTransportSettings( lul_device, lul_settings )
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.ChangeTransportSettings(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"NewTransportSettings=" .. lul_settings.NewTransportSettings,
						"CurrentAVTransportURI=" .. lul_settings.CurrentAVTransportURI}})
end

function actionAVTransportConfigureSleepTimer( lul_device, lul_settings )
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.ConfigureSleepTimer(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"NewSleepTimerDuration=" .. lul_settings.NewSleepTimerDuration}})
end

function actionAVTransportRunAlarm( lul_device, lul_settings )
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local _, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.SnoozeAlarm(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"Duration=" .. lul_settings.Duration}})
end

function actionAVTransportSetCrossfadeMode( lul_device, lul_settings )
	local device, uuid = controlByCoordinator(lul_device)
	local AVTransport = upnp.getService(uuid, UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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

	if (device ~= 0) then
		refreshNow(device, false, false)
	end
end

function actionAVTransportNotifyDeletedURI( lul_device, lul_settings )
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.NotifyDeletedURI(
		{OrderedArgs={"InstanceID=" .. instanceId,
						"DeletedURI=" .. lul_settings.DeletedURI}})
end

function actionAVTransportBecomeCoordinatorSG( lul_device, lul_settings )
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	AVTransport.BecomeCoordinatorOfStandaloneGroup({InstanceID=instanceId})
end

function actionAVTransportBecomeGroupCoordinator( lul_device, lul_settings )
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local AVTransport = upnp.getService(UUIDs[lul_device], UPNP_AVTRANSPORT_SERVICE)
	if (AVTransport == nil) then
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
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local desiredMute = defaultValue(lul_settings, "DesiredMute", nil)
	local channel = defaultValue(lul_settings, "Channel", "Master")

	-- If parameter is nill, we consider the callback as a toggle
	if (desiredMute == nil) then
		local isMuted = luup.variable_get(UPNP_RENDERING_CONTROL_SID, "Mute", lul_device)
		desiredMute = 1 - (tonumber(isMuted) or 0)
	end

	Rendering.SetMute(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "DesiredMute=" .. desiredMute}})

	refreshMuteNow(lul_device)
end

function actionRCResetBasicEQ( lul_device, lul_settings )
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.ResetBasicEQ({InstanceID=instanceId})
end

function actionRCResetExtEQ( lul_device, lul_settings )
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.ResetExtEQ(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "EQType=" .. lul_settings.EQType}})
end

function actionRCSetVolume( lul_device, lul_settings )
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local desiredVolume = tonumber(defaultValue(lul_settings, "DesiredVolume", "5"))
	local channel = defaultValue(lul_settings, "Channel", "Master")

	Rendering.SetVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "DesiredVolume=" .. desiredVolume}})

	refreshVolumeNow(lul_device)
end

function actionRCSetRelativeVolume( lul_device, lul_settings )
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local channel = defaultValue(lul_settings, "Channel", "Master")

	Rendering.SetRelativeVolume(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "Adjustment=" .. lul_settings.Adjustment}})

	refreshVolumeNow(lul_device)
end

function actionRCSetVolumeDB( lul_device, lul_settings )
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")
	local channel = defaultValue(lul_settings, "Channel", "Master")
	local desiredVolume = defaultValue(lul_settings, "DesiredVolume", "0")

	Rendering.SetVolumeDB(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. channel,
					 "DesiredVolume=" .. desiredVolume}})
end

function actionRCSetBass( lul_device, lul_settings )
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetBass(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "DesiredBass=" .. lul_settings.DesiredBass}})
end

function actionRCSetTreble( lul_device, lul_settings )
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetTreble(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "DesiredTreble=" .. lul_settings.DesiredTreble}})
end

function actionRCSetEQ( lul_device, lul_settings )
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetEQ(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "EQType=" .. lul_settings.EQType,
					 "DesiredValue=" .. lul_settings.DesiredValue}})
end

function actionRCSetLoudness( lul_device, lul_settings )
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetLoudness(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. lul_settings.Channel,
					 "DesiredLoudness=" .. lul_settings.DesiredLoudness}})
end

function actionRCSetOutputFixed( lul_device, lul_settings )
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.SetOutputFixed(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "DesiredFixed=" .. lul_settings.DesiredFixed}})
end

function actionRCRampToVolume( lul_device, lul_settings )
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
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
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
		return
	end

	local instanceId = defaultValue(lul_settings, "InstanceID", "0")

	Rendering.RestoreVolumePriorToRamp(
		 {OrderedArgs={"InstanceID=" .. instanceId,
					 "Channel=" .. lul_settings.Channel}})
end

function actionRCSetChannelMap( lul_device, lul_settings )
	local Rendering = upnp.getService(UUIDs[lul_device], UPNP_RENDERING_CONTROL_SERVICE)
	if (Rendering == nil) then
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
	local _, uuid = controlByCoordinator(lul_device)
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
	local _, uuid = controlByCoordinator(lul_device)
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
	local _, uuid = controlByCoordinator(lul_device)
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
	local _, uuid = controlByCoordinator(lul_device)
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
	refreshNow( lul_device, true, true )
	return 4,0
end
