--[[
	L_SonosTTS.lua - Implementation module for text-to-speech for the Sonos plugin for Luup
	Current maintainer: rigpapa https://community.getvera.com/u/rigpapa/summary
	For license information, see https://github.com/toggledbits/Sonos-Vera
--]]

module("L_SonosTTS", package.seeall)

VERSION = 19287
DEBUG_MODE = false

local url = require("socket.url")
local socket = require("socket")
local http = require("socket.http")
local https = require "ssl.https"
local ltn12 = require("ltn12")

local log = print
local warning = log
local error = log	--luacheck: ignore 231

local defaultLanguage
local defaultEngine
local MicrosoftClientId
local MicrosoftClientSecret
local accessToken
local accessTokenExpires

local engines = {}

local function debug(m, ...) if DEBUG_MODE then log(string.format("(tts debug) %s", tostring(m)), ...) end end

local function Q(str) return "'" .. string.gsub(tostring(str), "(')", "\\%1") .. "'" end

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

-- Abstract base class for TTS engine for this module. Although its abstract-ness is not strictly
-- enforced and this class can be instantiated directly to use for any HTTP-GET-method engine, the
-- intent is that the derived class provide any and all specifics, including parameters.
TTSEngine = {}
function TTSEngine:new(o)
	o = o or {}   -- create object if user does not provide one
	setmetatable(o, self)
	self.__index = self
	return o
end

-- say: retrieve audio file for text
function TTSEngine:say(text, language, destFile, engineOptions) end -- luacheck: ignore 212

-- HTTPGetTTSEngine - base class for HTTP GET-based TTS (extends TTSEngine).
HTTPGetTTSEngine = TTSEngine:new()
function HTTPGetTTSEngine:new(o)
	o = o or TTSEngine:new(o)
	setmetatable(o, self)
	self.__index = self
	return o
end
function HTTPGetTTSEngine:say(text, language, destFile, engineOptions)
	debug("say_http_get: engine " .. self.title .. " destFile " .. destFile .. " language " .. language .. " text " .. text)
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
				local s = param[n] or engineOptions[n] or self[n] or d or ""
				return f == "u" and url.escape(tostring(s)) or tostring(s)
			end)
		debug("say_http_get: requesting " .. tostring(cmd))
		local returnCode = os.execute(cmd)
		debug("say_http_get: returned " .. tostring(returnCode))
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
			warning(tostring(engine.title).." fetch command failed ("..tostring(returnCode).."); "..tostring(cmd))
			os.execute("rm -f -- " .. Q(destFile) .. " " .. Q(destFile .. ".part"))
			return nil, "Failed to retrieve audio file from remote API"
		end
		os.execute("rm -f -- " .. Q(destFile .. ".part"))
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
	fileType="mp3",
	bitrate=32,
	protocol="http-get:*:audio/mpeg:*",
	serverURL="https://code.responsivevoice.org",
	shellCmd=[[ rm -- '%{destFile:s}' ; curl -s -o '%{destFile:s}' \
--connect-timeout %{timeout:s|15} \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--header "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
'%{serverURL:s}/getvoice.php?t=%{text}&tl=%{lang|en_US}&sv=&vn=&pitch=%{pitch|0.5}&rate=%{rate|0.5}']],
	timeout=15,
	maxTextLength=100}
function ResponsiveVoiceTTSEngine:say( text, language, destFile, engineOptions )
	if not string.match( language, "^%w+%-%w+$" ) then
		warning("(tts) ResponsiveVoice typically requires two-part IETF language tags (e.g. 'en-US', 'de-DE', etc.). You provided '" .. tostring(language) .. "', which may not work.")
	end
	local lang = language:gsub("-","_")
	return HTTPGetTTSEngine.say( self, text, lang, destFile, engineOptions )
end

-- MaryTTS subclass
MaryTTSEngine = HTTPGetTTSEngine:new{
	title="MaryTTS",
	fileType="wav",
	bitrate=768, -- ??? was 256, but my Mary seems to produce higher rate; configurable?
	protocol="http-get:*:audio/wav:*",
	serverURL="http://127.0.0.1:59125",
	shellCmd=[[ rm -- '%{destFile:s}' ; curl -s -o '%{destFile:s}' \
--connect-timeout %{timeout|15} \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--header "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
"%{serverURL:s}/process?INPUT_TYPE=TEXT&AUDIO=WAVE_FILE&OUTPUT_TYPE=AUDIO&LOCALE=%{lang|en_US}&INPUT_TEXT=%{text}"]],
	timeout=15,
	maxTextLength=0}

GoogleTTSEngine = HTTPGetTTSEngine:new{
	title="Google TTS",
	fileType="mp3",
	bitrate=32,
	protocol="http-get:*:audio/mpeg:*", 
	serverURL="https://translate.google.com",
	shellCmd=[[rm -- '%{destFile:s}' ; wget --output-document '%{destFile:s}' \
--quiet \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
"%{serverURL:s}/translate_tts?tl=%{lang|en}&q=%{text}&client=Vera"]],
	timeout=15,
	maxTextLength=100}

OSXTTSEngine = HTTPGetTTSEngine:new{
	title="OSX TTS Server", 
	fileType="mp3",
	bitrate=64,
	protocol="http-get:*:audio/mpeg:*", 
	serverURL="http://127.0.0.1",
	shellCmd=[[rm -- '%{destFile:s}' ; wget --output-document '%{destFile:s}' \
--quiet \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
"%{serverURL:s}/tts?text=%{text}"]],
	timeout=15,
	maxTextLength=0}

-- Legacy engines

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


local function MicrosoftTTSwithToken(text, destFile, language, bitrate, token)
	local duration = nil

	local SAY_EXECUTE = "rm -- '%s' ; wget --output-document '%s' " .. [[ \
--quiet \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--header "Authorization: Bearer %s" \
--user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11" \
"http://api.microsofttranslator.com/V2/Http.svc/Speak?appId=&text=%s&language=%s&format=%s&options=%s"]]

	local returnCode = os.execute(SAY_EXECUTE:format(destFile, destFile, token, url.escape(text), language, url.escape("audio/mp3"), url.escape(MicrosoftOption)))
	local fh = io.open(destFile, "a+")
	local size = fh:seek("end")
	fh:close()

	if ((returnCode == 0) and (size > 0)) then
		-- MP3 file has a bitrate of 128 kbps (MaxQuality option) or 32 kbps (MinSize option)
		-- Add 1 second to be sure to not cut the end of the text
		duration = math.ceil(size/(bitrate/8*1000)) + 1
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

	return duration
end


local function MicrosoftTTS(text, destFile, language, bitrate)
	debug("Microsoft TTS: language " .. language .. " text " .. text)
	local duration

	local token = getMicrosoftAccessToken(false)
	if (token ~= nil) then
		duration = MicrosoftTTSwithToken(text, destFile, language, bitrate, token)
		if (duration or 0) == 0 then
			-- Try again with a new session token
			warning("Microsoft TTS: trying again with a new session token")
			token = getMicrosoftAccessToken(true)
			if (token ~= nil) then
				duration = MicrosoftTTSwithToken(text, destFile, language, bitrate, token)
			else
				warning("Microsoft TTS: can't get new session token")
			end
		end
	else
		warning("Microsoft TTS: can't get session token")
	end

	return duration
end

function setup(language, engine, googleUrl, osxUrl, maryUrl, rvURL, clientId, clientSecret, option)
	defaultLanguage = language or "en"
	defaultEngine = engine or "GOOGLE"
	engines.GOOGLE.serverURL = googleUrl or "http://translate.google.com"
	engines.MARY.serverURL = maryUrl or "http://127.0.0.1:3510"
	engines.RV.serverURL = rvURL or "https://code.responsivevoice.org"
	engines.OSX_TTS_SERVER.serverURL = osxUrl or "http://127.0.0.1"

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
	ident = ident or defaultEngine
	return (not (engines[ident] or {}).legacy) and engines[ident] or nil
end

function initialize(logger, warningLogger, errorLogger)
	log = logger
	warning = warningLogger
	error = errorLogger

	-- ??? FIXME Eventually, only register engines at first use.
	registerEngine( "GOOGLE", GoogleTTSEngine )
	registerEngine( "MARY", MaryTTSEngine )
	registerEngine( "RV", ResponsiveVoiceTTSEngine )
	registerEngine( "OSX_TTS_SERVER", OSXTTSEngine )

	-- Legacy Engines
	engines.MICROSOFT = { title = "Microsoft TTS", protocol = "http-get:*:audio/mpeg:*", fct = MicrosoftTTS, bitrate = 32, legacy=true }
	accessToken = nil
	accessTokenExpires = nil

	setup()
end

-- Convert text to speech audio in named file.
function ConvertTTS(text, destFile, language, engineId, engineOptions)
	-- Convert text to speech using specified engine
	language = language or defaultLanguage
	engine = engines[engineId or defaultEngine]
	engineOptions = engineOptions or {}
	debug("ConvertTTS engine "..tostring(engineId).." language "..tostring(language).." text "..tostring(text))
	if not engine then
		return nil, string.format("Engine not registered (%s)", tostring(engineId or defaultEngine))
	elseif engine.legacy then
		return engine.fct(text, destFile, language, engine.bitrate)
	else
		local duration,err = engine:say( text, language, destFile, engineOptions )
		if not duration then 
			warning("(tts) engine " .. (engine.title or "title?") .. " error: " .. tostring(err))
			return nil, err
		end
		return duration
	end
end
