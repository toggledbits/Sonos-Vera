--[[
	L_SonosTTS.lua - Implementation module for text-to-speech for the Sonos plugin for Luup
	Current maintainer: rigpapa https://community.getvera.com/u/rigpapa/summary
	For license information, see https://github.com/toggledbits/Sonos-Vera
--]]

module("L_SonosTTS", package.seeall)

VERSION = 19276
DEBUG_MODE = false

local url = require("socket.url")
local socket = require("socket")
local http = require("socket.http")
local https = require "ssl.https"
local ltn12 = require("ltn12")

local log = print
local warning = log
local error = log	--luacheck: ignore 231

local play
local localBaseURL
local localBasePath
local defaultLanguage
local defaultEngine
local MicrosoftClientId
local MicrosoftClientSecret
local accessToken
local accessTokenExpires
local Rate
local Pitch

local engines = {}
local sayQueue = {}
local cacheTTS = true

local DELETE_EXECUTE = "rm -f -- '%sSay.%s.*'"

local METADATA = [[<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
	<item id="VERA_TTS" parentID="-1" restricted="1">
		<dc:title>%s</dc:title>
		<res protocolInfo="%s">%s</res>
		<upnp:class>object.item.audioItem.musicTrack</upnp:class>
	</item>
</DIDL-Lite>]]

local function debug(...) if DEBUG_MODE then log(...) end end

-- cut_text: split long text to smaller than cutSize. Some engines have limits on the length
--            of the text to be converted. This function facilities a multi-request approach
--            to creating a combined single audio file.
local function cut_text( text, cutSize )
	-- Cut the text in fragments of config.maxTextLength chars
	if cutSize <= 0 then
		return { text }
	end
	local tableTextFragments = {}
	local remaining = text
	while #remaining > 0 do
		local pos = string.find(string.reverse(string.sub(remaining, 1, cutSize+1)), " ")
		if pos ~= nil then
			table.insert(tableTextFragments, string.sub(remaining, 1, cutSize+1-pos))
			remaining = string.sub(remaining, cutSize+3-pos)
		else
			if #remaining > 0 then table.insert(tableTextFragments, remaining) end
			remaining = ""
		end
	end
	return tableTextFragments
end

local function nullPlay()
	error("'play' function undefined--did you provide it to setup()?")
end
play = nullPlay

local function defaultValue(arr, val, default)
	return ((arr or {})[val] or "") == "" and default or arr[val]
end

-- Abstract base class for TTS engine for this module. Although its abstract-ness is not strictly
-- enforced and this class can be instantiated directly to use for any HTTP-GET-method engine, the
-- intent is that the derived class provide any and all specifics, including parameters.
TTSEngine = {}
function TTSEngine:new(o)
	o = o or {}   -- create object if user does not provide one
	setmetatable(o, self)
	self.__index = self
	self.fileType = "mp3"
	self.bitrate = o.bitrate or 32
	self.protocol = o.protocol or "http-get:*:audio/mpeg:*"
	self.lang = "en-US"
	self.rate = 0.5
	self.pitch = 0.5
	self.configured = false
	return o
end

-- Abstract: do any necessary configuration on device. Subclasses must call superclass method.
function TTSEngine:configure() self.configured = true end

-- say: retrieve audio file for text
function TTSEngine:say(text, language, destFile) end

-- HTTPGetTTSEngine - base class for HTTP GET-based TTS (extends TTSEngine).
HTTPGetTTSEngine = TTSEngine:new()
function HTTPGetTTSEngine:new(o)
	o = o or TTSEngine:new()
	setmetatable(o, self)
	self.__index = self
	self.serverURL = o.serverURL or "http://127.0.0.1"
	self.shellCmd = o.shellCmd or [[rm -- '%{destFile:s}';curl -s -o '${destFile}' %{serverURL:s}/tts?text=%{text}]]
	self.timeout = 15
	self.maxTextLength = o.maxTextLength or 0
	return o
end
function HTTPGetTTSEngine:say(text, language, destFile)
	if not self.configured then
		self:configure()
	end
	debug("say_http_get: destFile " .. destFile .. " language " .. language .. " text " .. text)
	local param = { lang=language, destFile=destFile, text=text }

	local txlist = cut_text( text:gsub("%s+", " "), self.maxTextLength or 0 )
	if #txlist == 0 or (#txlist == 1 and txlist[1]:match("^%s*$")) then return nil, "Empty text" end -- empty text
	local fw, size = 0
	if #txlist > 1 then
		-- Open combined output file for cut text
		fw = io.open(destFile, "w")
		if fw == nil then return nil, "Can't open output file" end
	end
	-- Do request parts
	for _,chunk in ipairs(txlist) do
		if #txlist > 1 then
			-- For cut text, set up this chunk
			param.text = chunk
			param.destFile = destFile .. ".part"
		end
		local cmd = self.shellCmd:gsub("%%%{([^%}]+)%}", function( p )
				local n,d = string.match(p, "^([^|]+)|?(.*)$")
				local m,f = string.match(n or "", "^([^:]+):(.*)$")
				if m then n = m else f = "u" end
				local s = param[n] or self[n] or d or ""
				return f == "u" and url.escape(tostring(s)) or tostring(s)
			end)
		debug("(tts) say_http_get: requesting " .. tostring(cmd))
		local returnCode = os.execute(cmd)
		debug("(tts) say_http_get: returned " .. tostring(returnCode))
		if returnCode == 0 then
			if #txlist > 1 then
				-- Add chunk to combined output
				local fh = io.open(param.destFile, "rb")
				while true do
					local s = fh:read(2048)
					if not s then break end
					fw:write(s)
				end
				fh:close()
			end
		else
			os.execute("rm -f -- '" .. destFile .. "' '" .. destFile .. ".part'")
			return nil, "Failed to retrieve audio file"
		end
		os.execute("rm -f -- '" .. destFile .. ".part'")
	end
	if #txlist == 1 then
		-- Single chunk, open output file for size
		fw = io.open(destFile, "rb")
	end
	if not fw then
		return nil, "No output file"
	end
	size = fw:seek("end")
	fw:close()
	if size > 0 then
		-- Convert bitrate in Kbps to Bps, and from that compute clip duration (aggressive rounding up)
		return math.ceil( size / ( self.bitrate * 125 ) ) + 1
	end
	debug("_say_http: received zero-length file")
	return nil, "Received zero-length file"
end

-- ResponsiveVoice subclass of TTSEngine
ResponsiveVoiceTTSEngine = HTTPGetTTSEngine:new{
	title="ResponsiveVoice",
	protocol="http-get:*:audio/mpeg:*",
	fileType="mp3",
	bitrate=32,
	maxTextLength=100,
	serverURL="https://code.responsivevoice.org",
	shellCmd=[[ rm -- '%{destFile:s}' ; curl -s -o '%{destFile:s}' \
--connect-timeout %{timeout:s|15} \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--header "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
'%{serverURL:s}/getvoice.php?t=%{text}&tl=%{lang|en_US}&sv=&vn=&pitch=%{pitch|0.5}&rate=%{rate|0.5}']]
}
function ResponsiveVoiceTTSEngine:say( text, language, destFile )
	if not string.match( language, "^%w+%-%w+$" ) then
		warning("(tts) ResponsiveVoice typically requires two-part IETF language tags (e.g. 'en-US', 'de-DE', etc.). You provided '" .. tostring(language) .. "', which may not work.")
	end
	local lang = language:gsub("-","_")
	return HTTPGetTTSEngine.say( self, text, lang, destFile )
end

-- MaryTTS subclass
MaryTTSEngine = HTTPGetTTSEngine:new{
	title="MaryTTS",
	protocol="http-get:*:audio/wav:*", 
	bitrate=256,
	fileType="wav",
	serverURL="http://127.0.0.1:59125",
	shellCmd=[[ rm -- '%{destFile:s}' ; curl -s -o '%{destFile:s}' \
--connect-timeout {timeout|15} \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--header "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
"%{serverURL:s}/process?INPUT_TYPE=TEXT&AUDIO=WAVE_FILE&OUTPUT_TYPE=AUDIO&LOCALE=%{lang|en}&INPUT_TEXT=%{text}"]]
}

GoogleTTSEngine = HTTPGetTTSEngine:new{
	title="Google TTS", 
	protocol="http-get:*:audio/mpeg:*", 
	bitrate=32,
	filetype="mp3",
	maxTextLength=100,
	serverURL="https://translate.google.com",
	shellCmd=[[rm -- '%{destFile:s}' ; wget --output-document '%{destFile:s}' \
--quiet \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
"%{serverURL:s}/translate_tts?tl=%{lang|en}&q=%{text}&client=Vera"]]
}

OSXTTSEngine = HTTPGetTTSEngine:new{
	title="OSX TTS Server", 
	protocol="http-get:*:audio/mpeg:*", 
	bitrate=64,
	fileType="mp3",
	serverURL="",
	shellCmd=[[rm -- '%{destFile:s}' ; wget --output-document '%{destFile:s}' \
--quiet \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
"%{serverURL:s}/tts?text=%{text}"]]
}

local function TTSEngineWrapper(engine, text, language, device)
	local destFile = string.format( "Say.%s.%s", tostring(device), engine.fileType or "mp3" )
	engine.rate = Rate or 0.5
	engine.pitch = Pitch or 0.5
	local duration,err = engine:say( text, language, localBasePath .. destFile )
	if duration then
		return duration, localBaseURL .. destFile, localBasePath .. destFile
	end
	warning("(tts) engine " .. (engine.title or "title?") .. " error: " .. tostring(err))
	return nil
end

-- Legacy engines

local SAY_OUTPUT_FILE = "%sSay.%s.%s"
local SAY_OUTPUT_URI = "%sSay.%s.%s"

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
			for _, v in ipairs(resultTable) do
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
			for _, v in ipairs(resultTable) do
				languages = languages .. v
			end
		end
	end

	return languages
end


local function MicrosoftTTSwithToken(text, language, device, bitrate, token)
	local duration = nil
	local uri = nil

	local SAY_EXECUTE = "rm -- '%s' ; wget --output-document '%s' " .. [[ \
--quiet \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--header "Authorization: Bearer %s" \
--user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
"http://api.microsofttranslator.com/V2/Http.svc/Speak?appId=&text=%s&language=%s&format=%s&options=%s"]]

	local file = SAY_OUTPUT_FILE:format(localBasePath, device, "mp3")
	local returnCode = os.execute(SAY_EXECUTE:format(file, file, token, url.escape(text), language, url.escape("audio/mp3"), url.escape(MicrosoftOption)))
	local fh = io.open(file, "a+")
	local size = fh:seek("end")
	fh:close()

	if ((returnCode == 0) and (size > 0)) then
		-- MP3 file has a bitrate of 128 kbps (MaxQuality option) or 32 kbps (MinSize option)
		-- Add 1 second to be sure to not cut the end of the text
		duration = math.ceil(size/(bitrate/8*1000)) + 1
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

	return duration, uri, file
end


local function MicrosoftTTS(text, language, device, bitrate)
	debug("Microsoft TTS: device " .. device .. " language " .. language .. " text " .. text)
	local duration, uri, file

	local token = getMicrosoftAccessToken(false)
	if (token ~= nil) then
		duration, uri, file = MicrosoftTTSwithToken(text, language, device, bitrate, token)
		if (uri == nil) then
			-- Try again with a new session token
			warning("Microsoft TTS: trying again with a new session token")
			token = getMicrosoftAccessToken(true)
			if (token ~= nil) then
				duration, uri, file = MicrosoftTTSwithToken(text, language, device, bitrate, token)
			else
				warning("Microsoft TTS: can't get new session token")
			end
		end
	else
		warning("Microsoft TTS: can't get session token")
	end

	return duration, uri, file
end

function setup(language, engine, playFct, baseURL, basePath, googleUrl, osxUrl, maryUrl, rvURL, clientId, clientSecret, option, rate, pitch)
	play = playFct or nullPlay
	defaultLanguage = language or "en"
	defaultEngine = engine or "GOOGLE"
	localBaseURL = baseURL
	localBasePath = basePath
	engines.GOOGLE.serverURL = googleUrl or "http://translate.google.com"
	engines.MARY.serverURL = maryUrl or "http://127.0.0.1:3510"
	engines.RV.serverURL = rvURL or "https://code.responsivevoice.org"
	engines.OSX_TTS_SERVER.serverURL = osxUrl or "http://127.0.0.1"
	Rate = rate
	Pitch = pitch

	-- Configure last remaining legacy engine. PHR 2019-10-03 Not sure if this engine still works
	-- or can be made to work.
	MicrosoftClientId = clientId
	MicrosoftClientSecret = clientSecret
	MicrosoftOption = option
	if (MicrosoftOption ~= nil and MicrosoftOption:find("MaxQuality")) then
		engines.MICROSOFT.bitrate = 128
	else
		engines.MICROSOFT.bitrate = 32
	end
end

-- Register an engine. The ident is a unique key for the engine passed in settings.engine to alert().
-- The engineInstance should be a fully-initialized, ready-to-use instance of a subclass of TTSEngine.
function registerEngine( ident, engineInstance )
	if engines[ident] then error("Engine already registered: " .. ident) end
	engines[ident] = engineInstance
end

function getEngine( ident )
	return (not (engines[ident] or {}).legacy) and engines[ident] or nil
end

function initialize(logger, warningLogger, errorLogger)
	log = logger
	warning = warningLogger
	error = errorLogger

	-- ??? FIXME Eventually, only register engines at first use.
	registerEngine( "GOOGLE", GoogleTTSEngine:new() )
	registerEngine( "MARY", MaryTTSEngine:new() )
	registerEngine( "RV", ResponsiveVoiceTTSEngine:new() )
	registerEngine( "OSX_TTS_SERVER", OSXTTSEngine:new() )

	-- Legacy Engines
	engines.MICROSOFT = { title = "Microsoft TTS", protocol = "http-get:*:audio/mpeg:*", fct = MicrosoftTTS, bitrate = 32, legacy=true }
	accessToken = nil
	accessTokenExpires = nil

	setup()
end

-- Quick and dirty hash for cache
local function hash(t)
	local s = #t
	for k=1,#t do
		s = ( s + t:byte(k) ) % 64
	end
	return s
end

local function Q(str) return "'" .. string.gsub(tostring(str), "(')", "\\%1") .. "'" end

local function fexists(fn) local f = io.open(fn, "r") if f then f:close() return true end return false end

local function loadTTSCache( engine, language, hashcode )
	local json = require "dkjson"
	local curl = string.format( "ttscache/%s/%s/%d/", tostring(engine), tostring(language), tostring(hashcode) )
	local cpath = localBasePath .. curl
	local fm = io.open( cpath .. "ttsmeta.json", "r" )
	if fm then
		local fmeta = json.decode( fm:read("*a") )
		fm:close()
		if fmeta and fmeta.version == 1 and fmeta.strings then
			return fmeta
		end
		warning("(tts) clearing cache " .. tostring(cpath))
		os.execute("rm -rf -- " .. Q(cpath))
	end
	return { version=1, nextfile=1, strings={} }, curl
end

local function alert(device, settings)
	if (settings.URI or "" ) == "" then
		-- TTS case

		local text = defaultValue(settings, "Text", "42")
		text = url.unescape(text:gsub("%+", "%%20"))
		local language = defaultValue(settings, "Language", defaultLanguage)
		local engine = defaultValue(settings, "Engine", defaultEngine)

		cacheTTS = not fexists( localBasePath .. "no-sonos-tts-cache" )
		if cacheTTS then
			local fmeta = loadTTSCache( engine, language, hash(text) )
			if fmeta.strings[text] then
				settings.Duration = fmeta.strings[text].duration
				settings.URI = localBaseURL .. fmeta.strings[text].url
				settings.URIMetadata = METADATA:format(engines[engine].title, engines[engine].protocol,
					settings.URI or "")
				log("(tts) speaking phrase from cache: " .. tostring(settings.URI))
			end
		end
		if (settings.URI or "") ~= "" then
			warning("(tts) text has already been converted to audio")
		elseif engines[engine] then
			-- Convert text to speech using specified engine
			local file
			if engines[engine].legacy then
				settings.Duration, settings.URI, file = engines[engine].fct(text, language, device, engines[engine].bitrate)
			else
				settings.Duration, settings.URI, file = TTSEngineWrapper(engines[engine], text, language, device)
			end
			if (settings.Duration or 0) == 0 then
				warning("(tts) "..tostring(engine).." produced no audio")
				return
			end
			settings.URIMetadata = METADATA:format(engines[engine].title, engines[engine].protocol,
				settings.URI)
			log("(tts) "..tostring(engine).." created "..tostring(settings.URI))
			if cacheTTS then
				-- Save in cache
				local fmeta, curl = loadTTSCache( engine, language, hash(text) )
				local cpath = localBasePath .. curl
				local ft = file:match("[^/]+$"):match("%.[^%.]+$") or ""
				os.execute("mkdir -p " .. Q(cpath))
				while true do
					local zf = io.open( cpath .. fmeta.nextfile .. ft, "r" )
					if not zf then break end
					zf:close()
					fmeta.nextfile = fmeta.nextfile + 1
				end
				if os.execute( "cp -f -- " .. Q( file ) .. " " .. Q( cpath .. fmeta.nextfile .. ft ) ) ~= 0 then
					warning("(tts) cache failed to copy "..Q( file ).." to "..Q( cpath..fmeta.nextfile..ft ))
				else
					fmeta.strings[text] = { duration=settings.Duration, url=curl .. fmeta.nextfile .. ft, created=os.time() }
					fm = io.open( cpath .. "ttsmeta.json", "w" )
					if fm then
						local json = require "dkjson"
						fmeta.nextfile = fmeta.nextfile + 1
						fm:write(json.encode(fmeta))
						fm:close()
						debug("(tts) cached " .. file .. " as " .. fmeta.strings[text].url)
					else
						warning("(ttscache) can't write cache meta in " .. cpath)
					end
				end
			end
		else
			warning("No TTS engine implementation for "..tostring(engine))
		end
	end
	debug("(tts) say " .. tostring(settings.URI))
	play(device, settings, true)
end

function queueAlert(device, settings)
	debug("TTS queueAlert for device " .. device)
	if not sayQueue[device] then sayQueue[device] = {} end
	table.insert(sayQueue[device], settings)
	-- First one kicks things off
	if #sayQueue[device] == 1 then
		alert(device, settings)
	end
end

-- Callback
function endPlayback(device)
	debug("TTS endPlayback for device " .. device)
	table.remove(sayQueue[device], 1)
	if #sayQueue[device] == 0 then
		os.execute(DELETE_EXECUTE:format(localBasePath, device))
		return true
	end
	alert(device, sayQueue[device][1])
	return false
end
