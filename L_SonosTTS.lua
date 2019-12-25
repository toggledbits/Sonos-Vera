--[[
	L_SonosTTS.lua - Implementation module for text-to-speech for the Sonos plugin for Luup
	Current maintainer: rigpapa https://community.getvera.com/u/rigpapa/summary
	For license information, see https://github.com/toggledbits/Sonos-Vera
--]]

module("L_SonosTTS", package.seeall)

VERSION = 19346
DEBUG_MODE = false
DEFAULT_LANGUAGE = "en-US"
DEFAULT_ENGINE = "RV"

local urllib = require("socket.url")
local socket = require("socket")
local http = require("socket.http")
local https = require "ssl.https"
local ltn12 = require("ltn12")

local base = _G

local log = print
local warning = log
local error = log	--luacheck: ignore 231

local defaultLanguage = DEFAULT_LANGUAGE
local defaultEngine = DEFAULT_ENGINE
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
	-- Canonicalize whitespace: trim ends, multis remaining are converted to single space
	local remaining = tostring(text):gsub( "^%s+", "" ):gsub( "%s+$", "" ):gsub( "%s+", " " )
	if cutSize <= 0 or #remaining <= cutSize then
		return { remaining }
	end
	local tableTextFragments = {}
	while #remaining > 0 do
		if #remaining <= cutSize then
			table.insert( tableTextFragments, remaining )
			return tableTextFragments
		end
		local pos = string.find(string.reverse(string.sub(remaining, 1, cutSize+1)), " ") or cutSize
		local chunk = string.sub( remaining, 1, cutSize-pos+1 )
		table.insert( tableTextFragments, chunk )
		remaining = string.sub( remaining, cutSize+3-pos )
	end
end

-- Abstract base class for TTS engine for this module. Although its abstract-ness is not strictly
-- enforced and this class can be instantiated directly to use for any HTTP-GET-method engine, the
-- intent is that the derived class provide any and all specifics, including parameters.
TTSEngine = {}
function TTSEngine:new(o)
	o = o or {}   -- create object if user does not provide one
	setmetatable(o, self)
	self.__index = self
	self.optionMeta = {}
	return o
end
function TTSEngine:getOptionMeta()
	return self.optionMeta
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
	local param = { lang=language, file=destFile, text=text }

	local txlist = cut_text( text:gsub("%s+", " "), engineOptions.maxchunk or 0 )
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
			param.file = destFile .. ".part"
		end
		os.remove(param.file)
		local cmd = self.shellCmd:gsub("%%%{([^%}]+)%}", function( p )
				local n,d = string.match(p, "^([^|]+)|?(.*)$")
				local m,f = string.match(n or "", "^([^:]+):(.*)$")
				if m then n = m else f = "u" end
				local s = param[n] or engineOptions[n] or self.optionMeta[n].default or d or ""
				return f == "u" and urllib.escape(tostring(s)) or tostring(s)
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
			warning(tostring(self.title).." fetch command failed ("..tostring(returnCode).."); "..tostring(cmd))
			os.remove(destFile)
			os.remove(destFile .. ".part")
			return nil, "Failed to retrieve audio file from remote API"
		end
		os.remove(destFile .. ".part")
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
	shellCmd=[[curl -s -k -o '%{file:s}' \
--connect-timeout %{timeout:s|15} \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--header "User-Agent: %{useragent:s}" \
'%{url:s}/getvoice.php?t=%{text}&tl=%{lang|en_US}&sv=&vn=&pitch=%{pitch|0.5}&rate=%{rate|0.5}']],
	optionMeta={
		url={ index=1, title="Server URL", default="https://code.responsivevoice.org" },
		timeout={ title="Timeout (secs)", default=15 },
		maxchunk={ title="Max Text Chunk", default=100 },
		rate={ index=2, title="Rate (0-1)", default=0.5 },
		pitch={ index=3, title="Pitch (0-2)", default=0.5 },
		useragent={ title="User-Agent Header", default=[[Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11]] }
	}
}
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
	shellCmd=[[curl -s -k -o '%{file:s}' \
--connect-timeout %{timeout:s|15} \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
"%{url:s}/process?INPUT_TYPE=TEXT&AUDIO=WAVE_FILE&OUTPUT_TYPE=AUDIO&LOCALE=%{lang|en_US}&INPUT_TEXT=%{text}"]],
	optionMeta={
		url={ index=1, title="Server URL", default="http://127.0.0.1:59125" },
		timeout={ title="Timeout (secs)", default=15 },
		maxchunk={ title="Max Text Chunk", default=100 }
	}
}

GoogleTTSEngine = HTTPGetTTSEngine:new{
	title="Google TTS",
	fileType="mp3",
	bitrate=32,
	protocol="http-get:*:audio/mpeg:*",
	shellCmd=[[wget --quiet --timeout=%{timeout:s|15} --output-document '%{file:s}' \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--user-agent "%{useragent:s}" \
"%{url:s}/translate_tts?tl=%{lang|en}&q=%{text}&client=Vera"]],
	optionMeta={
		url={ index=1, title="Server URL", default="http://127.0.0.1:59125" },
		timeout={ title="Timeout (secs)", default=15 },
		maxchunk={ title="Max Text Chunk", default=100 },
		useragent={ title="User-Agent Header", default=[[Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11]] }
	}
}

OSXTTSEngine = HTTPGetTTSEngine:new{
	title="OSX TTS Server",
	fileType="mp3",
	bitrate=64,
	protocol="http-get:*:audio/mpeg:*",
	serverURL="http://127.0.0.1",
	shellCmd=[[wget --quiet --timeout=%{timeout:s|15} --output-document '%{destFile:s}' \
--header "Accept-Charset: utf-8;q=0.7,*;q=0.3" \
--header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
--user-agent "%{useragent:s}" \
"%{url:s}/tts?text=%{text}"]],
	optionMeta={
		url={ index=1, title="Server URL", default="http://127.0.0.1" },
		timeout={ title="Timeout (secs)", default=15 },
		maxchunk={ title="Max Text Chunk", default=100 },
		useragent={ title="User-Agent Header", default=[[Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11]] }
	}
}

-- Microsoft Azure TTS Engine
-- https://docs.microsoft.com/en-us/azure/cognitive-services/speech-service/rest-text-to-speech
AzureTTSEngine = TTSEngine:new()
function AzureTTSEngine:new(o)
	o = o or TTSEngine:new(o)
	setmetatable(o, self)
	self.__index = self
	self.title = "Azure Speech Service"
	self.lastToken = 0
	self.maxTokenLife = 570
	self.token = ""
	self.format = "audio-16khz-64kbitrate-mono-mp3"
	self.filetype = "mp3"
	self.bitrate = 64
	self.protocol = "http-get:*:audio/mpeg:*"
	self.optionMeta = {
		subkey={ index=1, title="Subscription Key", required=true, infourl="https://docs.microsoft.com/en-us/azure/cognitive-services/cognitive-services-apis-create-account?tabs=multiservice%2Cwindows" },
		region={ index=2, title="Region", default="eastus", values={"australiaeast","canadacentral","centralus","eastasia","eastus","eastus2","francecentral","centralindia","japaneast","koreacentral","northcentralus","northeurope","southcentralus","southeastasia","uksouth","westeurope","westus","westus2"}, unrestricted=true },
		voice={ index=3, title="Voice", default="en-US-JessaRUS", values={"en-US-GuyNeural","en-US-JessaNeural","de-DE-KatjaNeural","en-US-JessaRUS","de-DE-HeddaRUS","en-GB-HazelRUS","es-ES-HelenaRUS","fr-FR-HortenseRUS","ro-RO-Andrei","pt-BR-HeloisaRUS","nb-NO-HuldaRUS","sv-SE-HedvigRUS","zh-CN-HuihuiRUS"}, unrestricted=true, infourl="https://docs.microsoft.com/en-us/azure/cognitive-services/speech-service/language-support#text-to-speech" },
		timeout={ title="Timeout (secs)", default="15" }
	}
	return o
end
function AzureTTSEngine:say(text, language, destFile, engineOptions)
	assert( engineOptions.subkey, "Subscription key is required" )
	
	local tries = 0
	while tries < 2 do
		tries = tries + 1
		if os.time() - self.lastToken >= self.maxTokenLife then
			debug("AzureTTSEngine:say() token is expired, fetching new")
			local url = string.format("https://%s.api.cognitive.microsoft.com/sts/v1.0/issueToken",
				engineOptions.region or self.optionMeta.region.default)
			local cmd = string.format([[curl -s -o - -X POST %q -H "Content-length: 0" \
-H "Content-type: application/x-www-form-urlencoded" -H "Ocp-Apim-Subscription-Key: %s"]],
				url, engineOptions.subkey or "undefined")
			local fp = io.popen( cmd )
			local s = fp:read("*a") or ""
			fp:close()
			if s:match("error") then
				warning("AzureTTSEngine:say() failed to fetch token: "..s)
				local json = require "dkjson"
				local data,pos,err = json.decode( s )
				if not data then 
					error("Invalid response JSON")
				elseif data.error and data.error.code ~= 200 then
					error(string.format("Can't get token, error %s response, %s", tostring(data.error.code),
						tostring(data.error.message)))
				end
				error("Unparseable token response")
			end
			self.token = s
			self.lastToken = os.time()
		end

		local host = string.format("%s.tts.speech.microsoft.com", engineOptions.region or self.optionMeta.region.default )
		local payload = string.format([[<speak version="1.0" xml:lang="%s"><voice name="%s">%s</voice></speak>]],
			language or "en-us", engineOptions.voice or self.optionMeta.voice.default,
			text:gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$",""):gsub("%&","&amp;"):gsub("%>","&gt;"):gsub("%<","&lt;"))
		debug(string.format("AzureTTSEngine:say() host %q payload %s", host, payload))
		os.remove( destFile )
		local fp,ferr = io.open(destFile, "wb")
		if not fp then error("Unable to open "..tostring(destFile)..": "..tostring(ferr)) end
		http.TIMEOUT = engineOptions.timeout or self.optionMeta.timeout.default or 15
		local status, statusMsg = https.request{
			url = "https://" .. host .. "/cognitiveservices/v1",
				sink = ltn12.sink.file(fp, ferr),
				method = "POST",
				headers = {
					["X-Microsoft-OutputFormat"] = self.format,
					["Host"] = host,
					["Content-Type"] = "application/ssml+xml",
					["Content-Length"] = #payload,
					["Authorization"] = "Bearer " .. tostring(self.token)
				},
				source = ltn12.source.string(payload)
			}
		if statusMsg == 200 then
			if io.type(fp) == "file" then fp:close() end
			fp = io.open( destFile, "rb" )
			local size = fp:seek("end")
			fp:close()
			if size > 0 then
				-- Convert bitrate in Kbps to Bps, and from that compute clip duration (aggressive rounding up)
				return math.ceil( size / ( self.bitrate * 125 ) ) + 1, nil, size
			end
			return nil, "received zero-length file"
		elseif statusMsg == 401 then
			-- Authorization error; assume token has expired. Arm to re-request.
			debug("AzureTTSEngine:say() auth fail, arming for retry")
			self.lastToken = 0
		else
			warning("AzureTTSEngine:say() conversion request failed, "..tostring(statusMsg))
			return nil, "request failed "..tostring(statusMsg)
		end
	end
	warning("AzureTTSEngine:say() authorization failed with Azure service")
	return nil, "authorization failed"
end

-- Legacy engines

local function getMicrosoftAccessToken(force)
	local currentTime = os.time()
	if (force or (accessTokenExpires == nil) or (currentTime > accessTokenExpires)) then
		accessToken = nil
		local resultTable = {}
		local postBody = string.format("grant_type=client_credentials&client_id=%s&client_secret=%s&scope=http://api.microsofttranslator.com",
									   urllib.escape(MicrosoftClientId),
									   urllib.escape(MicrosoftClientSecret))
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

	local returnCode = os.execute(SAY_EXECUTE:format(destFile, destFile, token, urllib.escape(text), language, urllib.escape("audio/mp3"), urllib.escape(MicrosoftOption)))
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

-- Register an engine. The ident is a unique key for the engine passed in settings.engine to alert().
-- The engineInstance should be a fully-initialized, ready-to-use instance of a subclass of TTSEngine.
function registerEngine( ident, engineInstance )
	if engines[ident] then error("Engine already registered: " .. ident) end
	engines[ident] = engineInstance
end

function getEngines()
	return engines
end

function getEngine( ident )
	ident = ident or defaultEngine
	return (not (engines[ident] or {}).legacy) and engines[ident] or nil
end

function setDefaultEngine( ident )
	ident = ident or DEFAULT_ENGINE
	if not engines[ident] then base.error("Invalid/unregistered engine "..ident) end
	defaultEngine = ident
end

function setDefaultLanguge( lang )
	defaultLanguage = lang or DEFAULT_LANGUAGE
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
	registerEngine( "AZURE", AzureTTSEngine:new() )

	setup()
end

-- Convert text to speech audio in named file.
function generate(engine, text, destFile, language, engineOptions)
	-- Convert text to speech using specified engine
	language = language or defaultLanguage
	engine = engine or engines[defaultEngine]
	engineOptions = engineOptions or {}
	debug("generate engine "..tostring(engine.title).." language "..tostring(language).." text "..tostring(text))
	if not (engine and engine.say) then
		return nil, "Invalid engine"
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

--[[ ************************ LEGACY/DEPRECATED FUNCTIONS ********************** ]]

function ConvertTTS(text, destFile, language, engineId, engineOptions)
	return generate(engines[engineId or defaultEngine], text, destFile, language, engineOptions)
end

function setup(language, engine, googleUrl, osxUrl, maryUrl, rvURL, clientId, clientSecret, option)
	defaultLanguage = language or DEFAULT_LANGUAGE
	defaultEngine = engine or DEFAULT_ENGINE
	engines.GOOGLE.optionMeta.url.default = googleUrl or "http://translate.google.com"
	engines.MARY.optionMeta.url.default = maryUrl or "http://127.0.0.1:3510"
	engines.RV.optionMeta.url.default = rvURL or "https://code.responsivevoice.org"
	engines.OSX_TTS_SERVER.optionMeta.url.default = osxUrl or "http://127.0.0.1"
end
