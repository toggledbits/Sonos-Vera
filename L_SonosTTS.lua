module("L_SonosTTS", package.seeall)

local url = require("socket.url")
local socket = require("socket")
local http = require("socket.http")
local https = require "ssl.https"
local ltn12 = require("ltn12")

local log = print
local warning = print
local error = print

local play = nil
local localBaseURL
local defaultLanguage
local defaultEngine
local GoogleServerURL
local OSXserverURL
local MaryServerURL
local RVServerURL = "https://code.responsivevoice.org"
local MicrosoftClientId
local MicrosoftClientSecret
local accessToken
local accessTokenExpires

local sayQueue = {}

local engines = {
    GOOGLE = { title = "Google TTS", protocol = "http-get:*:audio/mpeg:*", fct = nil },
    OSX_TTS_SERVER = { title = "OSX TTS Server", protocol = "http-get:*:audio/mpeg:*", fct = nil },
    MICROSOFT = { title = "Microsoft TTS", protocol = "http-get:*:audio/mpeg:*", fct = nil },
    MARY = { title = "MaryTTS", protocol = "http-get:*:audio/wav:*", fct = nil },
    RV = { title = "ResponsiveVoice TTS", protocol = "http-get:*:audio/mpeg:*", fct = nil }
}

local LOCAL_BASE_WEB_URL = "http://%s:%d"

local SAY_TMP_FILE = "/tmp/Say.%s.%s.mp3"
local SAY_OUTPUT_FILE = "/www/Say.%s.%s"
local SAY_OUTPUT_URI = "%s/Say.%s.%s"
local CONCAT_EXECUTE = "cat %s > %s ; rm %s"
local DELETE_EXECUTE = "rm /www/Say.%s.*"

local METADATA = '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
                 .. '<item id="VERA_TTS" parentID="-1" restricted="1"><dc:title>%s</dc:title>%s<upnp:class>object.item.audioItem.musicTrack</upnp:class></item></DIDL-Lite>'



local function defaultValue(arr, val, default)
    if (arr == nil or arr[val] == nil or arr[val] == "") then
      return default
    else
      return arr[val]
    end
end


local function GoogleTTS(text, language, device)
    log("Google TTS: device " .. device .. " language " .. language .. " text " .. text)
    local duration = 0
    local uri = nil

    if (GoogleServerURL ~= nil and GoogleServerURL ~= "") then

        local SAY_EXECUTE = "rm %s ; wget --output-document %s" .. [[ \
--quiet \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
"%s/translate_tts?tl=%s&q=%s&client=Vera"]]

        -- Cut the text in fragments of max 100 characters
        local tableTextFragments = {}
        local cutSize = 100	
        local remaining = text
        while (#remaining > cutSize) do
            local pos = string.find(string.reverse(string.sub(remaining, 1, cutSize+1)), " ")
            if (pos ~= nil) then
                table.insert(tableTextFragments, string.sub(remaining, 1, cutSize+1-pos))
                remaining = string.sub(remaining, cutSize+3-pos)
            else
                remaining = ""
            end
        end
        if (#remaining > 0) then
            table.insert(tableTextFragments, remaining)
        end

        -- Get the MP3 files from Google
        local returnCocde
        local file = SAY_OUTPUT_FILE:format(device, "mp3")
        if (#tableTextFragments == 0) then
            return duration, uri
        elseif (#tableTextFragments == 1) then
            returnCocde = os.execute(SAY_EXECUTE:format(file, file, GoogleServerURL, language, url.escape(tableTextFragments[1])))
        else
            local listFiles = ""
            for i, v in ipairs(tableTextFragments)
            do
                local partFile = SAY_TMP_FILE:format(device, i)
                returnCocde = os.execute(SAY_EXECUTE:format(partFile, partFile, GoogleServerURL, language, url.escape(v)))
                listFiles = listFiles .. " " .. partFile
            end
            -- Concat the multiple MP3 files
            os.execute(CONCAT_EXECUTE:format(listFiles, file, listFiles))
        end

        -- Get the file size to deduce its playback duration
        local fh = io.open(file, "a+")
        local size = fh:seek("end")
        fh:close()

        if ((returnCocde == 0) and (size > 0)) then
            -- Compute the play duration from the file size (32 kbps)
            -- and add 1 second to be sure to not cut the end of the text
            duration = math.ceil(size/4000) + 1
            uri = SAY_OUTPUT_URI:format(localBaseURL, device, "mp3")
        else
            warning("Google TTS: failed!")
        end
    else
        warning("Google TTS: server URL is not defined")
    end

    return duration, uri
end

local function RV_TTS(text, language, device)
    log("RV TTS: device " .. device .. " language " .. language .. " text " .. text)
    local duration = 0
    local uri = nil

    if (RVServerURL ~= nil and RVServerURL ~= "") then

        local SAY_EXECUTE = "rm %s ; curl -o %s" .. [[ \
-s \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--header "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
"%s/getvoice.php?t=%s&tl=%s&sv=&vn=&pitch=&rate=%s"]]

				local rate = luup.variable_get("urn:micasaverde-com:serviceId:Sonos1","TTS_RV_rate",device) or ""
				if ((rate ~= nil) and (rate ~= "")) then
					local rateVal = tonumber(rate,10)
					if ((rateVal == nil) or (rateVal < 0) or (rateVal > 1)) then
						rate = ""
					else
						rate = rateVal
					end
				end

        -- Cut the text in fragments of max 100 characters
        local tableTextFragments = {}
        local cutSize = 100	
        local remaining = text
        while (#remaining > cutSize) do
            local pos = string.find(string.reverse(string.sub(remaining, 1, cutSize+1)), " ")
            if (pos ~= nil) then
                table.insert(tableTextFragments, string.sub(remaining, 1, cutSize+1-pos))
                remaining = string.sub(remaining, cutSize+3-pos)
            else
                remaining = ""
            end
        end
        if (#remaining > 0) then
            table.insert(tableTextFragments, remaining)
        end

        -- Get the MP3 files from responsivevoice
        local returnCocde
        local file = SAY_OUTPUT_FILE:format(device, "mp3")
        if (#tableTextFragments == 0) then
            return duration, uri
        elseif (#tableTextFragments == 1) then
luup.log("RV cmd is "..SAY_EXECUTE:format(file, file, RVServerURL, url.escape(tableTextFragments[1]), language,rate),2)
            returnCocde = os.execute(SAY_EXECUTE:format(file, file, RVServerURL, url.escape(tableTextFragments[1]), language,rate))
        else
            local listFiles = ""
            for i, v in ipairs(tableTextFragments)
            do
                local partFile = SAY_TMP_FILE:format(device, i)
                returnCocde = os.execute(SAY_EXECUTE:format(partFile, partFile, RVServerURL, url.escape(v), language,rate))
                listFiles = listFiles .. " " .. partFile
            end
            -- Concat the multiple MP3 files
            os.execute(CONCAT_EXECUTE:format(listFiles, file, listFiles))
        end

        -- Get the file size to deduce its playback duration
        local fh = io.open(file, "a+")
        local size = fh:seek("end")
        fh:close()

        if ((returnCocde == 0) and (size > 0)) then
            -- Compute the play duration from the file size (32 kbps)
            -- and add 1 second to be sure to not cut the end of the text
            duration = math.ceil(size/4000) + 1
            uri = SAY_OUTPUT_URI:format(localBaseURL, device, "mp3")
        else
            warning("RV TTS: failed!")
        end
    else
        warning("RV TTS: server URL is not defined")
    end

    return duration, uri
end

local function TTSServer(text, language, device)
    log("TTS server (ODX): device " .. device .. " language " .. language .. " text " .. text)
    local duration = 0
    local uri = nil

    if (OSXserverURL ~= nil and OSXserverURL ~= "") then

        local SAY_EXECUTE = "rm %s ; wget --output-document %s" .. [[ \
--quiet \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
"%s/tts?text=%s"]]

        local file = SAY_OUTPUT_FILE:format(device, "mp3")
        local returnCocde = os.execute(SAY_EXECUTE:format(file, file, OSXserverURL, url.escape(text)))
        local fh = io.open(file, "a+")
        local size = fh:seek("end")
        fh:close()
 
        if ((returnCocde == 0) and (size > 0)) then
            -- add 1 second to be sure to not cut the end of the text
            duration = math.ceil(size/8000) + 1
            uri = SAY_OUTPUT_URI:format(localBaseURL, device, "mp3")
        else
            warning("TTS server (ODX): failed!")
        end
    else
        warning("TTS server (ODX): server URL is not defined")
    end

    return duration, uri
end


local function getMicrosoftAccessToken(force)
    local currentTime = os.time()
    if (force or (accessTokenExpires == nil) or (currentTime > accessTokenExpires)) then
        accessToken = nil
        local resultTable = {}
        local postBody = string.format("grant_type=client_credentials&client_id=%s&client_secret=%s&scope=http://api.microsofttranslator.com",
                                       url.escape(MicrosoftClientId),
                                       url.escape(MicrosoftClientSecret))
        local status, statusMsg = https.request{
            url = "https://datamarket.accesscontrol.windows.net/v2/OAuth2-13",
            sink = ltn12.sink.table(resultTable),
            method = "POST",
            headers = {["Content-Length"] = postBody:len(),
                       ["Content-Type"] = "application/x-www-form-urlencoded"},
           source = ltn12.source.string(postBody),
        }
        if (status ~= nil and statusMsg == 200) then
            local data = ""
            for i, v in ipairs(resultTable) do
                data = data .. v
            end
            local token, expires = data:match('"access_token":"([^"]-)".-"expires_in":"([^"]-)"')
            if (token ~= nil and expires ~= nil) then
                accessToken = token
                -- Session token expires after 10 minutes
                -- Take a security of 30 seconds
                accessTokenExpires = currentTime + tonumber(expires) - 30
            end
        end
    end
    return accessToken
end


local function getMicrosoftLanguages()

    local languages = nil

    local token = getMicrosoftAccessToken(false)
    if (token ~= nil) then

        local authorization = "Bearer " .. token

        local sock = function()
            local s = socket.tcp()
            s:settimeout(5)
            return s
        end

        local resultTable = {}
        local status, statusMsg = http.request{
            url = "http://api.microsofttranslator.com/V2/Http.svc/GetLanguagesForSpeak",
            method = "GET",
            headers = {["Accept"] = "application/xml",
                       ["Authorization"] = authorization},
            create = sock,
            sink = ltn12.sink.table(resultTable)
        }
        if (status ~= nil and statusMsg == 200) then
            languages = ""
            for i, v in ipairs(resultTable) do
                languages = languages .. v
            end
        end
    end

    return languages
end


local function MicrosoftTTSwithToken(text, language, device, token)
    local duration = 0
    local uri = nil

    local SAY_EXECUTE = "rm %s ; wget --output-document %s" .. [[ \
--quiet \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--header "Authorization: Bearer %s" \
--user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
"http://api.microsofttranslator.com/V2/Http.svc/Speak?appId=&text=%s&language=%s&format=%s&options=%s"]]

    local file = SAY_OUTPUT_FILE:format(device, "mp3")
    local returnCocde = os.execute(SAY_EXECUTE:format(file, file, token, url.escape(text), language, url.escape("audio/mp3"), "MaxQuality"))
    local fh = io.open(file, "a+")
    local size = fh:seek("end")
    fh:close()

    if ((returnCocde == 0) and (size > 0)) then
        -- MP3 file has a bitrate of 24 kbps
        -- Add 1 second to be sure to not cut the end of the text
        duration = math.ceil(size/3000) + 1
        uri = SAY_OUTPUT_URI:format(localBaseURL, device, "mp3")
    else
        local languages = getMicrosoftLanguages()
        local lang = language:gsub("-", "%%-"):lower()
        if (languages ~= nil
                and languages:match("<string>(" .. lang .. ")</string>") == nil) then
            warning("Microsoft TTS: failed due to unavailable speaking language " .. language)
        else
            warning("Microsoft TTS: failed!")
        end
    end

    return duration, uri
end


local function MicrosoftTTS(text, language, device)
    log("Microsoft TTS: device " .. device .. " language " .. language .. " text " .. text)
    local duration = 0
    local uri = nil

    local token = getMicrosoftAccessToken(false)
    if (token ~= nil) then
        duration, uri = MicrosoftTTSwithToken(text, language, device, token)
        if (uri == nil) then
			-- Try again with a new session token
            warning("Microsoft TTS: trying again with a new session token")
            token = getMicrosoftAccessToken(true)
            if (token ~= nil) then
                duration, uri = MicrosoftTTSwithToken(text, language, device, token)
            else
                warning("Microsoft TTS: can't get session token")
            end
        end
    else
        warning("Microsoft TTS: can't get session token")
    end

    return duration, uri
end


local function getMaryTTSLanguages()

    local status, languages = luup.inet.wget(MaryServerURL .. "/locales", 5)
    if (status ~= 0) then
        languages = nil
    end
    return languages
end


local function MaryTTS(text, language, device)
    log("MaryTTS: device " .. device .. " language " .. language .. " text " .. text)
    local duration = 0
    local uri = nil

    local SAY_EXECUTE = "rm %s ; wget --output-document %s" .. [[ \
--quiet \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
"%s/process?INPUT_TYPE=TEXT&AUDIO=WAVE_FILE&OUTPUT_TYPE=AUDIO&LOCALE=%s&INPUT_TEXT=%s"]]

    local lang = language:gsub("-", "_")

    local file = SAY_OUTPUT_FILE:format(device, "wav")
    local returnCocde = os.execute(SAY_EXECUTE:format(file, file, MaryServerURL, lang, url.escape(text)))
    local fh = io.open(file, "a+")
    local size = fh:seek("end")
    fh:close()

    if ((returnCocde == 0) and (size > 0)) then
        -- WAV file has a bitrate of 256 kbps
        -- add 1 second to be sure to not cut the end of the text
        duration = math.ceil(size/32000) + 1
        uri = SAY_OUTPUT_URI:format(localBaseURL, device, "wav")
    else
        local languages = getMaryTTSLanguages()
        if (languages == nil) then
            warning("MaryTTS: failed due to unreachable server")
        else
            languages = "," .. languages:gsub("\n", ",")
            if (languages:match(",(" .. lang .. "),") == nil) then
                warning("MaryTTS: failed due to unavailable language " .. lang)
            else
                warning("MaryTTS: failed probably due to uninstalled voice")
            end
        end
    end

    return duration, uri
end


function initialize(logger, warningLogger, errorLogger)
    log = logger
    warning = warningLogger
    error = errorLogger

    engines.GOOGLE.fct = GoogleTTS
    engines.OSX_TTS_SERVER.fct = TTSServer
    engines.MICROSOFT.fct = MicrosoftTTS
    engines.MARY.fct = MaryTTS
    engines.RV.fct = RV_TTS

    accessToken = nil
    accessTokenExpires = nil

    setup(nil, nil, nil, nil, nil)
end


function setup(language, engine, playFct, baseURL, googleUrl, osxUrl, maryUrl, clientId, clientSecret)
    defaultLanguage = language or "en"
    defaultEngine = engine or "GOOGLE"
    play = playFct or engines.GOOGLE.fct
    if (baseURL == nil or baseURL == "") then
        local stdout = io.popen("GetNetworkState.sh ip_wan")
        local ip = stdout:read("*a")
        stdout:close()
        localBaseURL = LOCAL_BASE_WEB_URL:format(ip, 80)
    else
        localBaseURL = baseURL
    end
    GoogleServerURL = googleUrl
    OSXserverURL = osxUrl
    MaryServerURL = maryUrl
    MicrosoftClientId = clientId
    MicrosoftClientSecret = clientSecret
end


local function alert(device, settings)
    if (settings.URI == nil or settings.URI == "") then
        -- TTS case

        local text = defaultValue(settings, "Text", "The monkey is on the branch, the mouse is under the table")
        text = url.unescape(text:gsub("%+", "%%20"))
        local language = defaultValue(settings, "Language", defaultLanguage)
        local engine = defaultValue(settings, "Engine", defaultEngine)

        if (engines[engine] ~= nil and engines[engine].fct ~= nil) then
            settings.Duration, settings.URI = engines[engine].fct(text, language, device)
            settings.URIMetadata = METADATA:format(engines[engine].title, '<res protocolInfo="' .. engines[engine].protocol ..'">' .. (settings.URI or "") .. '</res>')
        end
    end

    play(device, settings, true)
end


function queueAlert(device, settings)
    log("TTS queueAlert for device " .. device)
    if (sayQueue[device] == nil) then
        sayQueue[device] = {}
    end
    table.insert(sayQueue[device], settings)
    if (#sayQueue[device] == 1) then
        alert(device, settings)
    end
end


function endPlayback(device)
    log("TTS endPlayback for device " .. device)
    local finished = false
    table.remove(sayQueue[device], 1)
    if (#sayQueue[device] == 0) then
        os.execute(DELETE_EXECUTE:format(device))
        finished = true
    else
        alert(device, sayQueue[device][1])
    end
    return finished
end


