--[[
    L_SonosUPnP.lua - Implementation module for UPnP for the Sonos plugin for Luup
    Current maintainer: rigpapa https://community.getvera.com/u/rigpapa/summary
    For license information, see https://github.com/toggledbits/Sonos-Vera
--]]

module("L_SonosUPnP", package.seeall)

VERSION = 20074
DEBUG_MODE = false

local url = require("socket.url")
local socket = require("socket")
local http = require("socket.http")
local ltn12 = require("ltn12")

-- 5 Second timeout
local HTTP_TIMEOUT = 5

local IPTABLES_PARAM = "-d 224.0.0.0/4 -j SNAT --to-source %s"
local IPTABLES_CMD = "iptables -t nat -%s POSTROUTING %s"

local UPNP_DISCOVERY = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 5\r\nST: %s\r\n\r\n"

local UPNP_REQUEST = [[<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<s:Body>
<u:%s xmlns:u="%s">%s</u:%s>
</s:Body>
</s:Envelope>]]

local DIDL_FORMAT=[[<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
<item id="%s" parentID="%s" restricted="true">
<res protocolInfo="x-file-cifs:*:audio/mpeg:*">%s</res>
<r:streamContent>%s</r:streamContent>
<upnp:albumArtURI>%s</upnp:albumArtURI>
<dc:title>%s</dc:title>
<upnp:class>%s</upnp:class>
<dc:creator>%s</dc:creator>
<upnp:album>%s</upnp:album>
<upnp:originalTrackNumber>%s</upnp:originalTrackNumber>
<r:albumArtist>%s</r:albumArtist>
</item>
</DIDL-Lite>
]]

local log = print
local warning = print
local error = print
local contentType
local Services = {}
local subscriptionQueue = {}

-- Shared tables indexed by Vera devices
local ips = {}
local playbackCxt = {}
local sayPlayback = {}
local UUIDs = {}

-- Shared tables indexed by Sonos UUIDs
local metaDataKeys = {}
local dataTable = {}

local function debug( stuff, ... )
    if DEBUG_MODE then log( "(UPnP) "..tostring(stuff), ... ) end
end

function initialize(logger, warningLogger, errorLogger, ct)
  log = logger
  warning = warningLogger
  error = errorLogger
  contentType = ct or 'text/xml; charset="utf-8"'
  return ips, playbackCxt, sayPlayback, UUIDs, metaDataKeys, dataTable
end

function decode(val)
      return val:gsub("&#38;", '&')
                :gsub("&#60;", '<')
                :gsub("&#62;", '>')
                :gsub("&#34;", '"')
                :gsub("&#39;", "'")
                :gsub("&lt;", "<")
                :gsub("&gt;", ">")
                :gsub("&quot;", '"')
                :gsub("&apos;", "'")
                :gsub("&amp;", "&")
end

local function encode(val)
      return val:gsub("&", "&amp;")
                :gsub("<", "&lt;")
                :gsub(">", "&gt;")
                :gsub('"', "&quot;")
                :gsub("'", "&apos;")
end

function unformatXML(val)
      return val:gsub("^%s+<", "<")
                :gsub(">%s+$", ">")
                :gsub(">%s+<", "><")
end

function createDIDL(resURI, creator, album, title, artist, streamContent, albumArtURI, trackNumber, class, id, parentID)
  return DIDL_FORMAT:format(encode(id or 1),
                            encode(parentID or -1),
                            encode(resURI or ""),
                            encode(streamContent or ""),
                            encode(albumArtURI or ""),
                            encode(title or "No title"),
                            encode(class or "object.item.audioItem.musicTrack"),
                            encode(creator or ""),
                            encode(album or ""),
                            encode(trackNumber or 1),
                            encode(artist or "No artist"))
end

-- Send a UPnP SUBSCRIBE to the UPnP device,
-- Return value on success:
--   SID (subscription ID) provided by the device.
--   Duration (in seconds) before the subscription must be renewed
-- Return value on failure:
--   nil
--   Reason for failure (string)
-- Code coming from Wemo plugin (function subscribeToDevice) and adjusted
function UPnP_subscribe(eventSubURL, callbackURL, renewalSID)

    -- Create a socket with a timeout.
    local sock = function()
        local s = socket.tcp()
        s:settimeout(HTTP_TIMEOUT)
        return s
    end

    local headers = {
        ["TIMEOUT"] = "Second-3600",
    }

    if (renewalSID) then
        -- Renewing, include SID header.
        headers["SID"] = renewalSID
    else
        -- New subscription, include CALLBACK and NT headers
        headers["CALLBACK"] = string.format("<%s>", callbackURL)
        headers["NT"] = "upnp:event"
    end

    -- Ask the device to inform the proxy about status changes.
    local request, code, respHeaders = http.request({
        url = eventSubURL,
        method = "SUBSCRIBE",
        headers = headers,
        create = sock,
    })

    if request == nil and code ~= "closed" then
        error("Failed (conn) to subscribe to " .. eventSubURL .. ": " .. code)
        return nil, code
    elseif code ~= 200 then
        error("Failed (error) to subscribe to " .. eventSubURL .. ": " .. code)
        return nil, code
    else
        local duration = respHeaders["timeout"]:match("Second%-(%d+)")
        debug("UPnP_subscribe() subscription confirmed, SID %1 with timeout %2", respHeaders.sid, duration)
        return respHeaders.sid, tonumber(duration)
    end
end


function UPnP_request(controlURL, action, servicetype, args)
  debug("UPnP_request(%1,%2,%3,%4)", controlURL, action, servicetype, args)
  local function table2XML(value)
    local result = ""

    if (args == nil) then
        return result
    end

    --
    -- Convert all the Number, Boolean and Table objects, and escape all the string
    -- values in the XML output stream
    --
    -- If value table has an entry OrderedArgs, we consider that all the values
    -- are set in this special entry and we bypass all the other values of the value table.
    -- In this particular case, this entry itself is a table of strings, each element of
    -- the table following the format "parameter=value"
    --
    if (value.OrderedArgs ~= nil and type(value.OrderedArgs) == "table") then
        for _, val in ipairs(value.OrderedArgs) do
            local e, v = val:match("([^=]+)=(.*)")
            if (e ~= nil) then
                if (v == nil) then
                    result = result .. string.format("<%s />", e)
                elseif (type(v) == "table") then
                    result = result .. table2XML(v)
                elseif (type(v) == "number") then
                    result = result .. string.format("<%s>%.0f</%s>", e, v, e)
                elseif (type(v) == "boolean") then
                    result = result .. string.format("<%s>%s</%s>", e, (v and "1" or "0"), e)
                else
                    result = result .. string.format("<%s>%s</%s>", e, encode(v), e)
                end
            end
        end
    else
        for e, v in pairs(value) do
            if (v == nil) then
                result = result .. string.format("<%s />", e)
            elseif (type(v) == "table") then
                result = result .. table2XML(v)
            elseif (type(v) == "number") then
                result = result .. string.format("<%s>%.0f</%s>", e, v, e)
            elseif (type(v) == "boolean") then
                result = result .. string.format("<%s>%s</%s>", e, (v and "1" or "0"), e)
            else
                result = result .. string.format("<%s>%s</%s>", e, encode(v), e)
            end
        end
    end

    return result
  end

  local postBody = string.format(UPNP_REQUEST, action, servicetype, table2XML(args), action)
  debug("UPnP_request() url=%1, body=%2", controlURL, postBody)

  --
  -- Execute the resulting URL, and collect the results as a Table
  --
  local t1 = socket.gettime()
  local resultTable = {}
  http.TIMEOUT = 15
  local status, statusMsg = http.request{
    url = controlURL,
    sink = ltn12.sink.table(resultTable),
    method = "POST",
    headers = {["accept"] = "*/*",
               ["SOAPAction"] = '"' .. servicetype .. "#" .. action .. '"',
               ["connection"] = "close",
               ["content-length"] = postBody:len(),
               ["content-type"] = contentType},
    source = ltn12.source.string(postBody),
  }
  local dt = socket.gettime() - t1
  if dt >= 1 then warning("UPnP_request() %1#%2 action took %3s (long)", servicetype, action, dt) end

  --
  -- Flatten the resultTable into a regular string
  --
  local data = table.concat( resultTable, "" )
  resultTable = nil -- luacheck: ignore 311

  if (status == nil) then
    --
    -- Handle TIMEOUT
    --
    return false, statusMsg or "An error occurred during the UPnP call"
  end

  if (tostring(statusMsg) == "200") then
    --
    -- Handle SUCCESS
    --
    debug("UPnP_request() status=%1 statusMsg=%2 result=%3", status, statusMsg, data)

    if (data == nil or data == "") then
      return true, ""
    else
      local pattern = string.format('<.-:Body><.-:%sResponse%%sxmlns:.-="urn:.-">(.*)</.-:%sResponse></.-:Body></.-:Envelope>',
                                    action, action)
      local value = unformatXML(data):match(pattern) or ""

      -- TODO: Handle UPnP Error responses
      -- TODO: Handle Non-Scalar results

      -- commented out and returns a simple string instead. Due to multiple tags (not nested though)
      --      [[local dataTable = {}
      --      for tagBegin, value, tagEnd in value:gmatch("<(.*)>(.*)</(.*)>") do
      --        print(tagBegin .. " -> " .. value .. " <- " .. tagEnd)
      --        dataTable[tagBegin] = value
      --      end

      --     return dataTable]]
      return true, value
    end
  else
    --
    -- UNKNOWN ERROR
    --
    error(string.format("UPnP_request (%s, %s): status=%s statusMsg=%s result=[%s]",
                      action or "no action",
                      servicetype or "no servicetype",
                      status or "no status",
                      statusMsg or "no message",
                      data or "no result"))

    assert("Unhandled Response statusMsg=" .. statusMsg)
  end
end -- function UPnP_request

--
-- Return a handle to a UPnP Service object.
-- This can be used to call arbitrary Service Methods on that service using dynamic naming foo.
--
function service(controlURL, servicetype, actions)
    local self = {}
    local mt = {}

    mt.__index = function(table, key)
        debug("service.__index: accessing non-existing function %1", key)

        local fn = function(...)
            if (actions[key]) then
                debug("service.__index: %1(%2, %3) called with parameter count=%4", key, controlURL, servicetype, select("#", ...))
                return UPnP_request(controlURL, key, servicetype, ...)
            else
                return false, "action not available"
            end
        end

        table[key] = fn
        return fn
    end

    setmetatable(self, mt)

    return self
end


--------------------------------------------------------------------------------
-- UPnP discovery
--------------------------------------------------------------------------------


function isDiscoveryPatchInstalled(ip)
    local cmd = IPTABLES_CMD:format("S", "")
    cmd = cmd .. "| grep \"^-A POSTROUTING " .. IPTABLES_PARAM:format(ip):gsub("%.", "\\.") .. "\""
    if (os.execute(cmd) == 0) then
        return true
    else
        return false
    end
end


function installDiscoveryPatch(ip)
    local resu = isDiscoveryPatchInstalled(ip)
    if (resu == false) then
        os.execute(IPTABLES_CMD:format("I", IPTABLES_PARAM:format(ip)))
        resu = isDiscoveryPatchInstalled(ip)
    end
    return resu
end


function uninstallDiscoveryPatch(ip)
    local resu = isDiscoveryPatchInstalled(ip)
    if (resu == true) then
        os.execute(IPTABLES_CMD:format("D", IPTABLES_PARAM:format(ip)))
        resu = isDiscoveryPatchInstalled(ip)
    end
    return not resu
end


function UPnP_discover(target)
    local devices = {}
    local udp = socket.udp()
    if udp then
		-- udp:setoption('broadcast', true)
		-- udp:setoption('dontroute', true)
        -- udp:setsockname('*', 1900)
        local result = udp:sendto(UPNP_DISCOVERY:format(target), "239.255.255.250", 1900)
        if result ~= nil then
            udp:settimeout(5)
            local endtime = os.time() + 15
            while endtime > os.time() do
                local peer, port
                result, peer, port = udp:receivefrom()
                if not result then
                    debug("UPnP_discover() receive timeout")
                    break
                else
                    --[[ Typical response:
HTTP/1.1 200 OK
CACHE-CONTROL: max-age = 1800
EXT:
LOCATION: http://192.168.0.53:1400/xml/device_description.xml
SERVER: Linux UPnP/1.0 Sonos/54.2-72031 (ZPS22)
ST: urn:schemas-upnp-org:device:ZonePlayer:1
USN: uuid:RINCON_48A6B813879001400::urn:schemas-upnp-org:device:ZonePlayer:1
X-RINCON-HOUSEHOLD: HHID_la6A8YyuuYAgE8yZKK7iCCEuboM
X-RINCON-BOOTSEQ: 18
X-RINCON-WIFIMODE: 0
X-RINCON-VARIANT: 1
HOUSEHOLD.SMARTSPEAKER.AUDIO: HHID_la6A8YyuuYAgE8yZKK7iCCEuboM.YwYHlZ-PEqUQuUW7NRgL
--]]

                    debug("UPnP_discover() receivefrom %2:%3", result, peer, port)
                    local location, ip, pp = result:match("[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:%s?(http://([%d%.]-):(%d+)/.-)\r\n")
                    local st = result:match("[Ss][Tt]:%s?(.-)\r\n")
                    local usn = result:match("[Uu][Ss][Nn]:%s*(.-)\r\n")
                    local udn = usn and usn:match("uuid:([^:]+)")
                    log("UPnP_discover() response from %1 usn %2, udn %2", ip, usn, udn)
                    log(result)
                    if st ~= target then
                        warning("Ignoring erroneous response from non-compliant device at %1 (%2); it's not the requested type (%3).", ip, st, target)
                    elseif (location ~= nil and ip ~= nil and pp ~= nil and st ~= nil) then
                        local new = true
                        for _,device in ipairs( devices ) do
                            if device.descriptionURL == location and device.st == st then
                                new = false
                                break
                            end
                        end
                        if new then
                            table.insert(devices, { descriptionURL=location, ip=ip, port=pp, st=st, udn=udn })
                        end
                    end
                end
            end
        end
        udp:close()
    end
    return devices
end


function scanUPnPDevices(deviceType, infos)
    local xml = "<devices>"
    local devices = UPnP_discover(deviceType)
    for _,dev in ipairs(devices or {}) do
        debug("scanUPnPDevices() fetching %1", dev.descriptionURL)
        local descrXML = UPnP_getDeviceDescription(dev.descriptionURL)
        if descrXML then
-- ??? debug
log("scanUPnPDevices() returned device description for %1", dev.descriptionURL)
log(descrXML)
            local values, found = getInfosFromDescription(descrXML, deviceType, infos)
            debug("scanUPnPDevices() getInfos response for %1 is %2 infos %3", descrXML, values, infos)
            -- ??? rigpapa 2020-02-24: This built-up XML isn't used anywhere and seems wasteful
            if found then
                xml = xml .. "<device>"
                xml = xml .. "<ip>" .. (dev.ip or "") .. "</ip>"
                xml = xml .. "<port>" .. (dev.port or "") .. "</port>"
                xml = xml .. "<descriptionURL>" .. (dev.descriptionURL or "") .. "</descriptionURL>"
                if (infos ~= nil) then
                    for _,tag in ipairs(infos) do
                        xml = xml .. "<" .. tag .. ">" .. (values[tag] or "") .. "</" .. tag .. ">"
                        dev[tag] = values[tag]
                    end
                end
                xml = xml .. "</device>"
            end
        end
    end
    xml = xml .. "</devices>"
    return xml, devices
end


function searchUPnPDevices(deviceType, name, ip)
    local devices = UPnP_discover(deviceType)
    for _,dev in ipairs(devices) do
        if (ip == nil or ip == "" or ip == dev.ip) then
            local descrXML = UPnP_getDeviceDescription(dev.descriptionURL)
            if (descrXML ~= nil) then
                local values = getInfosFromDescription(descrXML, deviceType, { "modelName" })
                if (values.modelName == name) then
                    return dev.descriptionURL
                end
            end
        end
    end
    return nil
end


--------------------------------------------------------------------------------
-- UPnP device and services description
--------------------------------------------------------------------------------


function UPnP_getDeviceDescription(descriptionURL)
    local status, xml = luup.inet.wget(descriptionURL, 5)
    if (status ~= 0) then
        error("UPnP_getDeviceDescription wget failed - status=" .. (status or "nil") .. " xml=" ..(xml or "nil"))
        xml = nil
    end
    return xml
end


function getInfosFromDescription(descriptionXML, deviceType, infos)
    local data = {}
    local foundType = true
    local value, devices
    if (infos ~= nil) then
        foundType = false
        local rootDevPart1, embeddedDevices, rootDevPart2 = descriptionXML:match("(<device%s?[^>]->.-)<deviceList%s?[^>]->(.-)</deviceList>(.-</device>)")
        if (rootDevPart1 == nil or rootDevPart2 == nil or embeddedDevices == nil) then
            devices = descriptionXML:match("(<device%s?[^>]->.*</device>)") or ""
        elseif (deviceType ~= nil) then
            devices = rootDevPart1 .. rootDevPart2 .. embeddedDevices
        else
            devices = rootDevPart1 .. rootDevPart2
        end
        for device in devices:gmatch("<device%s?[^>]->(.-)</device>") do
            value = device:match("<deviceType>(.+)</deviceType>")
            if (deviceType == nil or value == deviceType) then
                foundType = true
                for _,tag in ipairs(infos) do
                    value = device:match("<"..tag..">(.+)</"..tag..">")
                    if (value ~= nil) then
                        data[tag] = value
                    end
                end
            end
        end
    end
    return data, foundType
end


function getIconFromDescription(descriptionXML)
    local resultURL = nil
    local rootDevice, size, height, width, icnoURL
    local rootDevPart1, embeddedDevices, rootDevPart2 = descriptionXML:match("(<device%s?[^>]->.-)<deviceList%s?[^>]->(.-)</deviceList>(.-</device>)")
    if (rootDevPart1 == nil or rootDevPart2 == nil or embeddedDevices == nil) then
        rootDevice = descriptionXML:match("(<device%s?[^>]->.*</device>)") or ""
    else
        rootDevice = rootDevPart1 .. rootDevPart2
    end
    size = 0
    for icon in rootDevice:gmatch("<icon%s?[^>]->(.-)</icon>") do
        height = icon:match("<height>(.+)</height>")
        width = icon:match("<width>(.+)</width>")
        icnoURL = icon:match("<url>(.+)</url>")
        if (icnoURL ~= nil and height ~= nil and width ~= nil) then
            height = tonumber(height) or 0
            width = tonumber(width) or 0
            if (height >= width and height > size) then
                size = height
                resultURL = icnoURL
            elseif (height < width and width > size) then
                size = width
                resultURL = icnoURL
            end
        end
    end
    return resultURL
end


function getActionsFromSCPD(scpdURL)
    local actions = {}
    local name
    local status, xml = luup.inet.wget(scpdURL, 5)
    if (status == 0) then
        for action in xml:gmatch("<action>(.-)</action>") do
            name = action:match("<name>(.-)</name>")
            if (name ~= nil) then
                actions[name] = true
            end
        end
    else
        error("getActionsFromSCPD wget failed - status=" .. (status or "nil") .. " xml=" ..(xml or "nil"))
    end
    return actions
end


function getStateVariablesFromSCPD(scpdURL)
    local stateVariables = {}
    local name, dataType, range, minimum, maximum, step, list, values
    local status, xml = luup.inet.wget(scpdURL, 5)
    if (status == 0) then
        for variable in xml:gmatch("<stateVariable%s?[^>]->(.-)</stateVariable>") do
            name = variable:match("<name>(.-)</name>")
            dataType = variable:match("<dataType>(.-)</dataType>")
            range = variable:match("<allowedValueRange>(.-)</allowedValueRange>")
            if (range ~= nil) then
                minimum = range:match("<minimum>(.-)</minimum>")
                maximum = range:match("<maximum>(.-)</maximum>")
                step = range:match("<step>(.-)</step>")
            else
                minimum = nil
                maximum = nil
                step = nil
            end
            list = variable:match("<allowedValueList>(.-)</allowedValueList>")
            if (list ~= nil) then
                values = ""
                for value in list:gmatch("<allowedValue>(.-)</allowedValue>") do
                    if (values == "") then
                        values = value
                    else
                        values = values .. "," .. value
                    end
                end
            else
                values = nil
            end
            if (name ~= nil and dataType ~= nil) then
                stateVariables[name] = {}
                stateVariables[name].dataType = dataType
                if (minimum ~= nil) then
                    stateVariables[name].minimum = minimum
                end
                if (maximum ~= nil) then
                    stateVariables[name].maximum = maximum
                end
                if (step ~= nil) then
                    stateVariables[name].step = step
                end
                if (values ~= nil) then
                    stateVariables[name].allowedValueList = values
                end
            end
        end
    else
        error("getStateVariablesFromSCPD wget failed - status=" .. (status or "nil") .. " xml=" ..(xml or "nil"))
    end
    return stateVariables
end


function buildURL(baseURL, baseDirectory, path)
    if (path:sub(1,1) ~= "/") then
        path = baseDirectory .. path
    end
    return url.absolute(baseURL, path)
end


function getServicesFromDescription(descriptionXML, deviceType, baseURL, baseDirectory, subsetServices)
    local services = {}
    local value, devices, serviceType, serviceId, controlURL, eventSubURL
    if (subsetServices ~= nil) then
        local rootDevPart1, embeddedDevices, rootDevPart2 = descriptionXML:match("(<device%s?[^>]->.-)<deviceList%s?[^>]->(.-)</deviceList>(.-</device>)")
        if (rootDevPart1 == nil or rootDevPart2 == nil or embeddedDevices == nil) then
            devices = descriptionXML:match("(<device%s?[^>]->.*</device>)") or ""
        else
            devices = rootDevPart1 .. rootDevPart2 .. embeddedDevices
        end
        for device in devices:gmatch("<device%s?[^>]->(.-)</device>") do
            value = device:match("<deviceType>(.+)</deviceType>")
            if (deviceType == nil or value == deviceType) then
                for service in device:gmatch("<service%s?[^>]->(.-)</service>") do
                    serviceType = service:match("<serviceType>(.*)</serviceType>")
                    serviceId = service:match("<serviceId>(.*)</serviceId>")
                    controlURL = service:match("<controlURL>(.*)</controlURL>")
                    eventSubURL = service:match("<eventSubURL>(.*)</eventSubURL>")
                    scpdURL = service:match("<SCPDURL>(.*)</SCPDURL>")
                    if (serviceType ~= nil and serviceId ~= nil
                           and controlURL ~= nil and eventSubURL ~= nil
                           and scpdURL ~= nil) then
                        for _,service2 in ipairs(subsetServices) do
                            if (service2 == serviceType) then
                               services[serviceType] = {
                                       controlURL = buildURL(baseURL, baseDirectory, controlURL),
                                       eventSubURL = buildURL(baseURL, baseDirectory, eventSubURL),
                                       scpdURL = buildURL(baseURL, baseDirectory, scpdURL),
                                       serviceId = serviceId,
                                       actions = getActionsFromSCPD(buildURL(baseURL, baseDirectory, scpdURL)),
                                       object = nil }
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    return services
end


--------------------------------------------------------------------------------
-- Services management
--------------------------------------------------------------------------------


  function aresServicesLoaded(uuid)
    if (uuid ~= nil and uuid ~= "" and Services[uuid] ~= nil) then
        return true
    else
        return false
    end
  end

  function getService(uuid, serviceType)
    local s = nil
    if (aresServicesLoaded(uuid) and Services[uuid][serviceType] ~= nil) then
        s = Services[uuid][serviceType].object
    end
    return s
  end

  function getInfoStateVariables(uuid, serviceType)
    local result = nil
    if (aresServicesLoaded(uuid) and Services[uuid][serviceType] ~= nil and Services[uuid][serviceType].scpdURL ~= nil) then
        result = getStateVariablesFromSCPD(Services[uuid][serviceType].scpdURL)
    end
    return result
  end

  function resetServices(uuid)
    if (aresServicesLoaded(uuid)) then
        Services[uuid] = nil
    end
  end

  function addServices(uuid, descriptionURL, descriptionXML, subsetServices)
    if (uuid == nil or uuid == "") then
        return
    end

    local baseURL, baseDirectory = descriptionURL:match("(http://[%d%.]-:%d+)(/.-)[^/]*$")

    if (Services[uuid] == nil) then
        Services[uuid] = {}
    end

    for _,servicesForType in ipairs(subsetServices) do
        local services = getServicesFromDescription(
                                  descriptionXML, servicesForType[1],
                                  baseURL, baseDirectory,
                                  servicesForType[2])
        for k,v in pairs(services) do
            Services[uuid][k] = v
        end
    end

    for k,v in pairs(Services[uuid]) do
        debug("addServices() %1 %2 %3 %4 %5", k, v.serviceId, v.controlURL, v.eventSubURL, v.scpdURL)
        if (v.object == nil) then
            v.object = service(v.controlURL, k, v.actions)
        end
    end
  end


  function setup(descriptionURL, deviceType, infos, subsetServices)

    local descriptionXML = UPnP_getDeviceDescription(descriptionURL)
    if (descriptionXML == nil) then
        return false, false, "", {}, nil
    end

    local baseURL, baseDirectory = descriptionURL:match("(http://[%d%.]-:%d+)(/.-)[^/]*$")

    local found = false
    for _, info in ipairs(infos) do
        if (info == "UDN") then
            found = true
            break
        end
    end
    if (not found) then
        table.insert(infos, "UDN")
    end

    local values = getInfosFromDescription(descriptionXML, deviceType, infos)

    local uuid = values.UDN:match("uuid:(.+)") or ""

    local iconURL = getIconFromDescription(descriptionXML)
    if (iconURL ~= nil) then
        iconURL = buildURL(baseURL, baseDirectory, iconURL)
    end

    if (aresServicesLoaded(uuid) == false) then
        addServices(uuid, descriptionURL, descriptionXML, subsetServices)
    end

    return true, aresServicesLoaded(uuid), values, iconURL
  end



  function testURL(URLtoBeChecked, headers)
    local sock = function()
        local s = socket.tcp()
        s:settimeout(2)
        return s
    end

    if (headers == nil) then
        headers = {}
    end

    local request, code, resultHeaders = http.request({
        url = URLtoBeChecked,
        method = "HEAD",
        headers = headers,
        create = sock
    })

    if (request ~= nil and code == 200) then
        return true, resultHeaders
    else
        return false, {}
    end
  end


  --------------------------------------------------------------------------------
  -- UPnP AV metadata (DIDL-Lite parsing)
  --------------------------------------------------------------------------------


  -- parseElt(value, tag, subTag)
  -- Parse XML data at the second or third depth level
  -- If there are several elements, only the first is taken in consideration
  -- Parameters:
  --   value is the XML data
  --   tag is the first depth level XML tag
  --   subTag is the second depth level XML tag or nil if data have to be retrieved from the second depth level
  -- Return values:
  --   multilines string containing all parsed values; each line is formatted like that: tag="value"
  --   table containing parsed data (attributes + values) indexed either by the tag or tag@attribute
  function parseFirstElt(value, tag, subTag)
      local pattern = string.format("<%s(%%s?[^>]-)>(.*)</%s>", tag, tag)
      local attributes, tmp = value:match(pattern)
      if (tmp ~= nil and subTag ~= nil) then
          -- Get the content of the first sub tag
          pattern = string.format("<%s(%%s?[^>]-)>(.-)</%s>", subTag, subTag)
          attributes, tmp = tmp:match(pattern)
      end

      if (tmp == nil) then
          return nil, {}
      end

      local elts, eltsTable = "", {}

      for attr, value1 in attributes:gmatch('%s(.-)="(.-)"') do
          eltsTable["@" .. attr] = value1
      end

      for token, mattr, value1 in tmp:gmatch("<([a-zA-Z0-9:]+)(%s?[^>]-)>(.-)</[^>]->") do
          elts = elts .. string.format('%s="%s"\n', token, value1)
          eltsTable[token] = value1
          for attr, value2 in mattr:gmatch('%s(.-)="(.-)"') do
              eltsTable[token .. "@" .. attr] = value2
          end
      end

      return elts, eltsTable
  end

  -- parseDIDLItem(value)
  -- Parse XML data for the item of a DIDL UPnP AV defining metadata XML meta data
  -- Parameters:
  --   value is the DIDL XML data
  -- Return values:
  --   multilines string containing all parsed values; each line is formatted like that: tag="value"
  --   table containing parsed data (attributes + values) indexed either by the tag or tag@attribute
  function parseDIDLItem(value)
      return parseFirstElt(value, "DIDL%-Lite", "item")
  end


  local function extractElementValue(tag, xml)
    local result = nil
    if (xml ~= nil) then
        local pattern = string.format("<%s%%s?[^>]->", tag)
        local pos0, pos1 = xml:find(pattern)
        if pos0 and pos1 then
            if xml:sub(pos1-1, pos1-1) == "/" then
                result = ""
            else
                pattern = string.format("</%s>", tag)
                local pos2 = xml:find(pattern, pos1)
                if pos2 then
                    result = xml:sub(pos1+1, pos2-1)
                else
                    debug("upnp:extractElementValue() lost end for %1 in %2", tag, xml)
                end
            end
        else
            debug("upnp:extractElementValue() tag %1 not found in %2", tag, xml)
        end
    end
    return result
  end


  function extractElement(tag, xml, default)
    local result = default
    local value = extractElementValue(tag, xml)
    if (value ~= nil) then
        result = decode(value)
    end
    return result
  end


  function browseContent(uuid, serviceType, browseObj, onlyMetadata, filter, transformFct, timeout)
      local t0 = os.clock()
      local result = ""
      local ContentDirectory = getService(uuid, serviceType)
      if (ContentDirectory == nil) then
          return result
      end

      local browseFlag
      if (onlyMetadata) then
          browseFlag = "BrowseMetadata"
      else
          browseFlag = "BrowseDirectChildren"
      end

      local fetched = 0
      local total
      local status, tmp
      repeat
          status, tmp = ContentDirectory.Browse({OrderedArgs={
                                 "ObjectID=" .. browseObj,
                                 "BrowseFlag=" .. browseFlag,
                                 "Filter=" .. (filter or "*"),
                                 "StartingIndex=" .. string.format("%d", fetched),
                                 "RequestedCount=100",
                                 "SortCriteria="}})
          if (status == true) then
              local value = unformatXML(extractElement("Result", tmp, ""))
              if (fetched == 0 and transformFct == nil) then
                  local val = value:match("(<DIDL%-Lite%s?[^>]->.-)</DIDL%-Lite>")
                  if (val == nil) then
                      val = value:match("(<DIDL%-Lite%s?[^>]-/>)")
                      if (val ~= nil) then
                          val = val:sub(1, #val - 2) .. ">"
                      end
                  end
                  if (val ~= nil) then
                      result = val
                  end
              elseif (transformFct == nil and result ~= "") then
                  result = result .. (extractElementValue("DIDL%-Lite", value) or "")
              else
                  result = result .. (transformFct(value) or "")
              end
              fetched = fetched + tonumber(extractElement("NumberReturned", tmp, "0"))
              total = tonumber(extractElement("TotalMatches", tmp, "0"))
          else
              total = 0
          end
      until (fetched >= total or (timeout ~= nil and (os.clock() - t0) >= timeout))
      if (result ~= "" and transformFct == nil) then
          result = result .. "</DIDL-Lite>"
      end
      debug("browseContent() %1 duration %2s - %3 fetched elements - size result %4 timeout %5", browseObj, os.clock() - t0, fetched, #result, timeout)
      return result
  end


  --------------------------------------------------------------------------------
  -- UPnP Event Proxy
  --------------------------------------------------------------------------------


  -- XML pattern used when notifying the UPnP event proxy of the the subscription to an event
  local PROXY_REQUEST = "<subscription expiry='%d'><variable name='%s' host='localhost' deviceId='%d' serviceId='%s' action='%s' parameter='%s' sidParameter='sid'/></subscription>"

  -- Version of the UPnP event proxy, or nil if proxy is not running or not used
  local ProxyApiVersion = nil


  -- getProxyApiVersion()
  -- Calls the proxy with GET /version.
  -- Sets the ProxyApiVersion global variable to the value received
  -- Return value:
  --   nil if the proxy is not running.
  --   The proxy API version (as a string) otherwise.
  function getProxyApiVersion()
    local sock = function()
        local s = socket.tcp()
        s:settimeout(2)
        return s
    end

    local t = {}
    local request, code = http.request({
        url = "http://localhost:2529/version",
        create = sock,
        sink = ltn12.sink.table(t)
    })

    if (request == nil and code == "timeout") then
        -- Proxy may be busy.
        warning("Temporarily cannot communicate with proxy")
        return nil
    elseif (request == nil and code ~= "closed") then
        -- Proxy not running.
        warning("Cannot contact UPnP Event Proxy: " .. code)
        return nil
    else
        -- Proxy is running, note its version number.
        ProxyApiVersion = table.concat(t)
        return ProxyApiVersion
    end
  end


  -- WeMo plugin contrib
  -- proxyVersionAtLeast(n)
  -- Returns true if the proxy is running and is at least version n.
  function proxyVersionAtLeast(n)
    local v = tonumber(ProxyApiVersion or "")
    return v and v >= n or false
  end


  -- unuseProxy()
  -- Disable the usage of the UPnP event proxy by resetting the variable ProxyApiVersion to nil
  -- Return value: none
  function unuseProxy()
    ProxyApiVersion = nil
    warning("UPnP event proxy is now unused")
  end


-- Add a notification to the notification queue.
-- This queue will be sent on a timer
-- to make it easy for the server to process sonos proxy traffic
local function enqueueSubscription(sid, proxyRequestBody)
    table.insert(subscriptionQueue, {
        sid = sid,
        proxyRequestBody = proxyRequestBody
    })

    if #subscriptionQueue == 1 then
        luup.call_delay("processProxySubscriptions", 0, "Enqueued:" .. #subscriptionQueue )
    end
end


function processProxySubscriptions()
    if #subscriptionQueue > 0 then
        local subscription = table.remove(subscriptionQueue, 1)

        local sock = function()
            local s = socket.tcp()
            s:settimeout(2)
            return s
        end

        local t = {}

        local r = {
            url = "http://localhost:2529/upnp/event/" .. url.escape(subscription.sid),
            create = sock,
            sink = ltn12.sink.table(t)
        }

        if subscription.proxyRequestBody then
            r.method = "PUT"
            r.source = ltn12.source.string(subscription.proxyRequestBody)
            r.headers = {
                ["Content-Type"] = "text/xml",
                ["Content-Length"] = subscription.proxyRequestBody:len()
            }
        else
            r.method = "DELETE"
            r.source = ltn12.source.empty()
        end

        debug("processProxySubscriptions() send Proxy subscription request: %1 SID %2", r.method, subscription.sid )
        local request, reason = http.request(r)

        if request == nil and reason == "timeout" then
            debug("processProxySubscriptions() retry proxy subscription request: %1 SID %2", r.method, subscription.sid )
            table.insert(subscriptionQueue, subscription)
        elseif request == nil then
            debug("processProxySubscriptions() give up proxy subscription request %1 SID %2", r.method, subscription.sid )
        elseif  reason ~= 200 then
            local data = table.concat(t)
            debug("processProxySubscriptions() invalid proxy subscription request %1 SID %2 resp %3",
                r.method, subscription.sid, data )
        else
            debug("processProxySubscriptions() completed proxy subscription request %1 SID %2", r.method, subscription.sid )
        end

        if #subscriptionQueue > 0 then
            luup.call_delay("processProxySubscriptions", 0, "Enqueued:" .. #subscriptionQueue  )
        end
    end
end

  -- subscribeToUPnPEvent(device, veraIP, eventSubURL, eventVariable, actionServiceId, actionName, renewalSID)
  -- Process a new subscription to an event for an UPnP device, or renew an active subscription
  -- First send a subscription request to the UPnP device and then notify the proxy of this new subscription
  -- Parameters:
  --   device is the device id that the UPnP event proxy will notify
  --   veraIP is the IP address of the VERA
  --   eventSubURL is the URL to be used to subscribe to the UPnP device
  --   eventVariable is the UPnP variable name we subscribe to
  --   actionServiceId is the service id of the action to be called by the UPnP event proxy
  --   actionName is the action name to be called by the UPnP event proxy
  --   renewalSID is the subscription id to be renewed or nil if it is an initial subscription
  -- Return values:
  --   subscription id or nil if the subscribe process failed
  --   expiry date of the new or renewed subscription; nil if the subscribe process failed
  --   live duration of the new or renewed subscription; nil if the subscribe process failed
  function subscribeToUPnPEvent(device, veraIP, eventSubURL, eventVariable, actionServiceId, actionName, renewalSID)
    debug("subscribeToUPnPEvent(%1,%2,%3,%4,%5,%6,%7)", device, veraIP, eventSubURL, eventVariable, actionServiceId, actionName, renewalSID)

    -- Ask the device to inform the proxy about status changes.
    local callbackURL = string.format("http://%s:2529/upnp/event", veraIP)
    local expiry = nil
    local sid, duration = UPnP_subscribe(eventSubURL, callbackURL, renewalSID)
    if sid then
        expiry = os.time() + duration

        -- Tell proxy about this subscription and the variable we care about.
        -- Volume is the variable we care about.
        local proxyRequestBody = PROXY_REQUEST:format(expiry, eventVariable, device, actionServiceId, actionName, eventVariable)
        enqueueSubscription(sid, proxyRequestBody)
    end

    return sid, expiry, duration
  end


  -- WeMo plugin contrib
  -- cancelProxySubscription(sid)
  -- Sends a DELETE /upnp/event/[sid] message to the UPnP event proxy,
  function cancelProxySubscription(sid)
    debug("Cancelling subscription for sid %1", sid)
    enqueueSubscription(sid)
  end


  -- subscribeToEvents(device, veraIP, subscriptions, actionServiceId, uuid)
  -- Process the subscription to several events for an UPnP device, or renew these subscriptions
  -- The subscriptions are defined in a table (subscriptions).
  -- Each element of this table is enhanced with subsciption data (id, expiry date, ...).
  -- Before calling this function, the UPnP services for the UPnP device have to be loaded. Only
  -- events associated to a loaded and registered service will be subscribed to.
  -- If one event subscription fails, all subscriptions are finally cancelled.
  -- A timer is set to call the function renewSubscriptions, so that all the subscritopns can be
  -- renewed in time. So this function "renewSubscriptions" must be declared by the plugin.
  -- Parameters:
  --   device is the device id that the UPnP event proxy will notify
  --   veraIP is the IP address of the VERA
  --   subscriptions is a table defining the events to be subscribed to
  --   actionServiceId is the service id for all actions to be called by the UPnP event proxy
  --   uuid is the UUID of the UPnP device
  -- Return value:
  --   true if UPnP event proxy is not running or not used
  --   true if the UPnP services are not yet loaded and registered
  --   true if all subscriptions succeeded
  --   false if subscriptions failed
  function subscribeToEvents(device, veraIP, subscriptions, actionServiceId, uuid)
    debug("subscribeToEvents(%1,%2,%3,%4,%5)", device, veraIP, subscriptions, actionServiceId, uuid)

    if not proxyVersionAtLeast(1) then
       debug("subscribeToEvents() event subscription postponed, proxy is not running. device %1", device )
--     luup.call_delay("renewSubscriptions", 30, device .. ":" .. uuid)
       return true
    end
    if (aresServicesLoaded(uuid) == false) then
       debug("subscribeToEvents() event subscription postponed, services are not loaded yet. device %1", device )
--     luup.call_delay("renewSubscriptions", 30, device .. ":" .. uuid)
      return true
    end

    local result = true

    local sid, expiry, duration

    local nbSubscriptions = 0
    local minDuration = 0

    for _,subscription in ipairs(subscriptions) do
        if (Services[uuid][subscription.service] ~= nil) then
            sid = nil
            if (subscription.id or "") ~= "" then
                sid = subscription.id
                debug("subscribeToEvents() sid present; attempting renewal (%1)", sid)
            end
            subscription.id = ""
            subscription.expiry = ""
			subscription.error = nil
            sid, expiry, duration = subscribeToUPnPEvent(device,
                                                         veraIP,
                                                         Services[uuid][subscription.service].eventSubURL,
                                                         subscription.eventVariable,
                                                         actionServiceId,
                                                         subscription.actionName,
                                                         sid)
            if sid then
                debug("subscribeToEvents() event subscription succeeded => SID %1 duration %2 expiry %3",
                    sid, duration, expiry)
                subscription.id = sid
                subscription.expiry = expiry
                nbSubscriptions = nbSubscriptions + 1
                if minDuration <= 0 or duration < minDuration then
                    minDuration = duration
                end
            else
                warning("Event subscription failed for %1 service %2: %3 error %4", uuid,
                    subscription.service, Services[uuid][subscription.service].eventSubURL,
                    duration)
                subscription.error = duration
                --[[ Not getting a subscription should not be a fatal error.
                cancelProxySubscriptions(subscriptions)
                nbSubscriptions = 0
                result = false
                break
                --]]
            end
        else
            warning("Event subscription for %2 service %1 ignored, unregistered service",
                subscription.service, uuid)
            subscription.error = "unregistered"
        end
    end

    if result and nbSubscriptions > 0 and minDuration > 0 then
        -- Renew at larger of 80% time or time-60. Otherwise, we're in a race condition for renewal.
        local delay = math.max( math.floor( minDuration * 0.80 ), minDuration - 60 )
        debug("subscribeToEvents() renew delay %1 for %2:%3 minDuration %4", delay, device, uuid, minDuration)
        luup.call_delay("renewSubscriptions", delay, device .. ":" .. uuid)
    else
        debug("subscribeToEvents() no subscription renewal, result=%1, num=%2, dur=%3",
            result, nbSubscriptions, minDuration)
    end

    return result, nbSubscriptions
  end


  -- cancelProxySubscriptions(subscriptions)
  -- Sends a DELETE /upnp/event/[sid] message to the UPnP event proxy for all subscriptions
  -- defined in the table subscriptions.
  -- Subscription data for each element of this table are reset.
  -- Parameters:
  --   subscriptions is a table containing the current subscription data
  -- Return value: none
  function cancelProxySubscriptions(subscriptions)
    debug("cancelProxySubscriptions(%1)", subscriptions)

    if not proxyVersionAtLeast(1) then
        return
    end

    for _,subscription in ipairs(subscriptions) do
        if (subscription.id ~= "") then
            cancelProxySubscription(subscription.id)
            subscription.id = ""
            subscription.expiry = ""
        end
    end
  end

  -- isValidNotification(notifyAction, sid, subscriptions)
  -- Check whether a proxy notification is valid (the subscription id has to be declared in the
  -- table containing current subscription data)
  -- If not, a delayed action cancelProxySubscription is called to unsubscribe this subscription.
  -- So this function "cancelProxySubscription" must be declared by the plugin.
  -- Parameters:
  --   notifyAction is the action called by the UPnP event proxy
  --   sid is the subscription id provided by the UPnP event proxy
  --   subscriptions is a table containing the current subscription data
  -- Return value:
  --   true if the proxy notification is valid
  --   false if the proxy notification is not valid
  function isValidNotification(notifyAction, sid, subscriptions)
    if not proxyVersionAtLeast(1) then
        warning("Call to " .. notifyAction .. " while proxy is not used")
    else
        for _,subscription in ipairs(subscriptions) do
            if subscription.id == sid then
                return true
            end
        end
        warning("Call to " .. notifyAction .. " with bad SID " .. sid)
    end
    -- Try to shut the proxy up, we don't care about this SID.
    luup.call_delay("cancelProxySubscription", 1, sid)
    return false
  end
