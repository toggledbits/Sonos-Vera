--[[
	L_SonosTTS.lua - Implementation module for text-to-speech for the Sonos plugin for Luup
	Current maintainer: rigpapa https://community.getvera.com/u/rigpapa/summary
	For license information, see https://github.com/toggledbits/Sonos-Vera
--]]

module("L_SonosTTS", package.seeall)

VERSION = 20286
DEBUG_MODE = true

local urllib = require("socket.url")
local http = require("socket.http")
local ssl = require "ssl"
local https = require "ssl.https"
local ltn12 = require("ltn12")

local base = _G

local log = print
local warning = log
local error = log	--luacheck: ignore 231

local defaultEngine = "MARY"

local engines = {}

local function debug(m, ...) if DEBUG_MODE then log('(tts debug) '..m, ...) end end

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

local function xmlescape( t ) return ( t:gsub( '"', "&quot;" ):gsub( "'", "&apos;" ):gsub( "%&", "&amp;" ):gsub( "%<", "&lt;" ):gsub( "%>", "&gt;" ) ) end

-- Abstract base class for TTS engine for this module. Although its abstract-ness is not strictly
-- enforced and this class can be instantiated directly to use for any HTTP-GET-method engine, the
-- intent is that the derived class provide any and all specifics, including parameters.
TTSEngine = {}
function TTSEngine:new(o)
	o = o or {}   -- create object if user does not provide one
	setmetatable(o, self)
	self.__index = self
	self.lang = "en-US" -- default language for engine
	self.optionMeta = {}
	return o
end
function TTSEngine:getOptionMeta()
	return self.optionMeta
end

-- say: retrieve audio file for text
function TTSEngine:say(text, destFile, engineOptions) end -- luacheck: ignore 212

-- HTTPGetTTSEngine - base class for HTTP GET-based TTS (extends TTSEngine).
HTTPGetTTSEngine = TTSEngine:new()
function HTTPGetTTSEngine:new(o)
	o = o or TTSEngine:new(o)
	setmetatable(o, self)
	self.__index = self
	return o
end
function HTTPGetTTSEngine:say(text, destFile, engineOptions)
	debug("say_http_get: engine " .. self.title .. " destFile " .. destFile .. " text " .. text)
	local param = { file=destFile, text=text }

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
		return math.ceil( size / ( self.bitrate * 128 ) ) + 1
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
	lang="en_US", -- default language for engine
	optionMeta={
		url={ index=1, title="Server URL", default="https://code.responsivevoice.org" },
		lang={ index=2, title="Language", default="en_US", unrestricted=true, values={
						['en_AU']="English (Australian)",
						['en_CA']="English (Canadian)",
						['en_GB']="English (British)",
						['en_US']="English (American)",
						['el_GR']="Greek",
						['nl_NL']="Dutch",
						['fi_FI']="Finnish",
						['fr_CA']="French (Canadian)",
						['fr_FR']="French (French)",
						['de_DE']="German",
						['hu_HU']="Hungarian",
						['it_IT']="Italian",
						['nb_NO']="Norwegian",
						['pt_BR']="Portugese (Brazilian)",
						['pt_PT']="Portugese (Portugese)",
						['ru_RU']='Russian',
						['es_mx']="Spanish (Mexican)",
						['es_es']="Spanish (Spanish)",
						['sv_SE']="Swedish",
						['tr_TR']="Turkish"
			}
		},
		timeout={ title="Timeout (secs)", default=15 },
		maxchunk={ title="Max Text Chunk", default=100 },
		rate={ index=2, title="Rate (0-1)", default=0.5 },
		pitch={ index=3, title="Pitch (0-2)", default=0.5 },
		useragent={ title="User-Agent Header", default=[[Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11]] }
	}
}

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
'%{url:s}?INPUT_TYPE=TEXT&AUDIO=WAVE_FILE&OUTPUT_TYPE=AUDIO&LOCALE=%{lang|en-US}&INPUT_TEXT=%{text}&{extraopts:s}']],
	optionMeta={
		url={ index=1, title="Server URL", default="http://127.0.0.1:59125/process" },
		lang={ index=2, title="Language", default="en-US", unrestricted=true, values={
						['en']="English",
						['en-GB']="English (British)",
						['en-US']="English (American)",
						['en-CA']="English (Canadian)",
						['en-AU']="English (Australian)",
						['nl']="Dutch",
						['fr']="French",
						['fr-CA']="French (Canadian)",
						['fr-FR']="French (French)",
						['de']="German",
						['it']="Italian",
						['pt']="Portugese",
						['pt-BR']="Portugese (Brazilian)",
						['pt-PT']="Portugese (Portugese)",
						['ru']='Russian',
						['es']="Spanish",
						['es-mx']="Spanish (Mexican)",
						['es-es']="Spanish (Spanish)"
			}
		},
		maxchunk={ index=3, title="Max Text Chunk", default=100 },
		timeout={ index=4, title="Timeout (secs)", default=15 },
		extraopts={ index=5, title="Extra Params", default="" }
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
"%{url:s}?tl=%{lang|en}&q=%{text}&client=Vera"]],
	optionMeta={
		url={ index=1, title="Server URL", default="https://translate.google.com/translate_tts" },
		lang={ index=2, title="Language", default="en-US", unrestricted=true, values={
						['en']="English",
						['en-GB']="English (British)",
						['en-US']="English (American)",
						['en-CA']="English (Canadian)",
						['en-AU']="English (Australian)",
						['nl']="Dutch",
						['fr']="French",
						['fr-CA']="French (Canadian)",
						['fr-FR']="French (French)",
						['de']="German",
						['it']="Italian",
						['pt']="Portugese",
						['pt-BR']="Portugese (Brazilian)",
						['pt-PT']="Portugese (Portugese)",
						['ru']='Russian',
						['es']="Spanish",
						['es-mx']="Spanish (Mexican)",
						['es-es']="Spanish (Spanish)"
			}
		},
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
		lang={ index=2, title="Language", default="en-US", unrestricted=true, values={
						['en']="English",
						['en-GB']="English (British)",
						['en-US']="English (American)",
						['en-CA']="English (Canadian)",
						['en-AU']="English (Australian)",
						['nl']="Dutch",
						['fr']="French",
						['fr-CA']="French (Canadian)",
						['fr-FR']="French (French)",
						['de']="German",
						['it']="Italian",
						['pt']="Portugese",
						['pt-BR']="Portugese (Brazilian)",
						['pt-PT']="Portugese (Portugese)",
						['ru']='Russian',
						['es']="Spanish",
						['es-mx']="Spanish (Mexican)",
						['es-es']="Spanish (Spanish)"
			}
		},
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
		voice={ index=3, title="Voice", default="en-US-JessaRUS", values={
				["ar-EG-Hoda"]="Arabic (Egypt), female",
				["ar-SA-Naayf"]="Arabic (Saudi Arabia), male",
				["bg-BG-Ivan"]="Bulgarian",
				["ca-ES-HerenaRUS"]="Catalan (Spain), female",
				["cs-CZ-Jakub"]="Czech, male",
				["da-DK-HelleRUS"]="Danish, female",
				["de-AT-Michael"]="German (Austria), male",
				["de-CH-Karsten"]="German (Switzerland), male",
				["de-DE-Hedda"]="German (Germany), female",
				["de-DE-HeddaRUS"]="German (Germany), female, alternate",
				["de-DE-Stefan-Apollo"]="German (Germany), male",
				["de-DE-KatjaNeural"]="German (Germany), female, neural",
				["el-GR-Stefanos"]="Greek, male",
				["en-AU-Catherine"]="English (Australia), female",
				["en-AU-CatherineRUS"]="English (Australia), female, alternate",
				["en-CA-Linda"]="English (Canada), female (Linda)",
				["en-CA-HeatherRUS"]="English (Canada), female (Heather)",
				["en-GB-Susan-Apollo"]="English (UK), female (Susan)",
				["en-GB-HazelRUS"]="English (UK), female (Hazel)",
				["en-GB-George-Apollo"]="English (UK), male (George)",
				["en-IE-Sean"]="English (Ireland), male",
				["en-IN-Heera-Apollo"]="English (India), female (Heera)",
				["en-IN-PriyaRUS"]="English (India), female (Priya)",
				["en-IN-Ravi-Apollo"]="English (India), male (Ravi)",
				["en-US-JessaRUS"]="English (US), female (Jessa, standard)",
				["en-US-ZiraRUS"]="English (US), female (Zira)",
				["en-US-BenjaminRUS"]="English (US), male (Benjamin)",
				["es-ES-HelenaRUS"]="Spanish (Spain), female (Helena)",
				["en-US-GuyNeural"]="English (US), male (Guy, neural)",
				["en-US-JessaNeural"]="English (US), female (Jessa, neural)",
				["es-ES-Laura-Apollo"]="Spanish (Spain), female (Laura)",
				["es-ES-Pablo-Apollo"]="Spanish (Spain), male (Pablo)",
				["es-MX-HildaRUS"]="Spanish (Mexico), female (Hilda)",
				["es-MX-Raul-Apollo"]="Spanish (Mexico), male (Raul)",
				["fi-FI-HeidiRUS"]="Finnish, female",
				["fr-CA-HarmonieRUS"]="French (Canada), female (Harmonie)",
				["fr-CA-Caroline"]="French (Canada), female (Caroline)",
				["fr-CH-Guillaume"]="French (Switzerland), male",
				["fr-FR-HortenseRUS"]="French (France), female (Hortense)",
				["fr-FR-Julie-Apollo"]="French (France), female (Julie)",
				["fr-FR-Paul-Apollo"]="French (France), male (Paul)",
				["he-IL-Asaf"]="Hebrew (Israel), male",
				["hi-IN-Kalpana"]="Hindi (India), female",
				["hi-IN-Kalpana-Apollo"]="Hindi (India), female alternate",
				["hi-IN-Hemant"]="Hindi (India), male",
				["hr-HR-Matej"]="Croatian, male",
				["hu-HU-Szabolcs"]="Hungarian, male",
				["id-ID-Andika"]="Indonesian, male",
				["it-IT-Cosimo-Apollo"]="Italian (Italy), male",
				["it-IT-LuciaRUS"]="Italian (Italy), female",
				["it-IT-ElsaNeural"]="Italian (Italy), female, neural",
				["ja-JP-Ayumi-Apollo"]="Japanese, female (Ayumi)",
				["ja-JP-Ichiro-Apollo"]="Japanese, male (Ichiro)",
				["ja-JP-HarukaRUS"]="Japanese, female (Haruka)",
				["ko-KR-HeamiRUS"]="Korean, female",
				["ms-MY-Rizwan"]="Malay, male",
				["nb-NO-HuldaRUS"]="Norwegian, female",
				["nl-NL-HannaRUS"]="Dutch, female",
				["pl-PL-PaulinaRUS"]="Polish, female",
				["pt-BR-HeloisaRUS"]="Portugese (Brazil), female",
				["pt-BR-Daniel-Apollo"]="Portugese (Brazil), male",
				["pt-PT-HeliaRUS"]="Portugese (Portugal), female",
				["ro-RO-Andrei"]="Romanian, male",
				["ru-RU-Irina-Apollo"]="Russian, female (Irina)",
				["ru-RU-Pavel-Apollo"]="Russian, male (Pavel)",
				["ru-RU-EkaterinaRUS"]="Russian, female (Ekaterina)",
				["sk-SK-Filip"]="Slovak, male",
				["sl-SI-Lado"]="Slovenian, male",
				["sv-SE-HedvigRUS"]="Swedish, female",
				["ta-IN-Valluvar"]="Tamil (India), male",
				["te-IN-Chitra"]="Telugu (India), female",
				["th-TH-Pattara"]="Thai, male",
				["tr-TR-SedaRUS"]="Turkish, female",
				["vi-VN-An"]="Vietnamese, male",
				["zh-CN-HuihuiRUS"]="Chinese (Mainland), female (Huihui)",
				["zh-CN-Yaoyao-Apollo"]="Chinese (Mainland), female (Yaoyao)",
				["zh-CN-Kangkang-Apollo"]="Chinese (Mainland), male (Kangkang)",
				["zh-CN-XiaoxiaoNeural"]="Chinese (Mainland), female, neural",
				["zh-HK-Tracy-Apollo"]="Chinese (Hong Kong), female (Tracy)",
				["zh-HK-TracyRUS"]="Chinese (Hong Kong), female (Tracy, alternate)",
				["zh-HK-Danny-Apollo"]="Chinese (Hong Kong), male (Danny)",
				["zh-TW-Yating-Apollo"]="Chinese (Taiwan), female (Yating)",
				["zh-TW-HanhanRUS"]="Chinese (Taiwan), female (Hanhan)",
				["zh-TW-Zhiwei-Apollo"]="Chinese (Taiwan), male (Zhiwei)"
			},
			unrestricted=true,
			infourl="https://docs.microsoft.com/en-us/azure/cognitive-services/speech-service/language-support#text-to-speech"
		},
		timeout={ title="Timeout (secs)", default="15" },
		requestor={ title="Requestor", default="", values={ [""]="LuaSocket/LuaSec (recommended)", ["C"]="curl" } }
	}
	return o
end
function AzureTTSEngine:say(text, destFile, engineOptions)
	assert( engineOptions.subkey, "Subscription key is required" )
	local tries = 0
	while tries < 3 do
		tries = tries + 1
		if os.time() - self.lastToken >= self.maxTokenLife then
			debug("AzureTTSEngine:say() token is expired, fetching new")
			local url = string.format("https://%s.api.cognitive.microsoft.com/sts/v1.0/issueToken",
				engineOptions.region or self.optionMeta.region.default)
			local cmd = string.format([[curl -s -k -o - -m 15 -X POST -H 'Content-length: 0' \
-H 'Content-type: application/x-www-form-urlencoded' -H 'Ocp-Apim-Subscription-Key: %s' '%s']],
				((engineOptions.subkey or "undefined"):gsub( "'", "\\'" )), url)
			debug("AzureTTSEngine:say() %1", cmd)
			local fp = io.popen( cmd )
			local s = fp:read("*a") or ""
			fp:close()
			debug("AzureTTSEngine:say() response %1", s)
			if s:match("error") then
				warning("AzureTTSEngine:say() failed to fetch token: "..s)
				local json = require "dkjson"
				local data = json.decode( s )
				if not data then
					debug("AzureTTSEngine:say() invalid response JSON: %1", s)
					error("Invalid response JSON")
					break
				elseif data.error and data.error.code ~= 200 then
					error("Can't get token, error %1 response, %2", data.error.code, data.error.message)
					break
				end
				error("Unparseable token response")
			elseif s == "" then
				error("Empty response, likely failed to negotiate SSL or invalid URL")
			end
			self.token = s
			self.lastToken = os.time()
			debug("AzureTTSEngine:say() acquired new token %1", self.token)
		else
			debug("AzureTTSEngine:say() current token assumed valid")
		end

		local host = string.format("%s.tts.speech.microsoft.com", engineOptions.region or self.optionMeta.region.default )
		local voice = engineOptions.voice or self.optionMeta.voice.default
		local lang = voice:gsub( "^(%w+%-%w+)%-.*", "%1" )
		local payload = string.format('<speak version="1.0" xml:lang="%s"><voice name="%s"><![CDATA[%s]]></voice></speak>',
			lang, voice, text:gsub("'", "\\'"))
		debug("AzureTTSEngine:say() host %1 payload %2", host, payload)
		debug("AzureTTSEngine:say() system LuaSec version is %1", ssl._VERSION)
		os.remove( destFile )
		if engineOptions.requestor == "C" or (ssl._VERSION or ""):match( "^0%.[54]" ) then
			-- Ancient LuaSec, or curl specified
		   local fp = io.open(destFile .. "-curl.sh", "w")
		   fp:write( "#!/bin/sh\n# This file is automatically generated; DO NOT EDIT\n\n" )
		   fp:write( string.format("rm -f -- '%s'\n", destFile) )
		   fp:write( string.format("curl -s -k -m %s -X POST -o '%s' \\\n",
				   engineOptions.timeout or self.optionMeta.timeout.default or 15,
				   destFile) )
		   fp:write( string.format(" -H 'Host: %s' \\\n", host) )
		   fp:write( string.format(" -H 'Authorization: Bearer %s' \\\n", self.token) )
		   fp:write( string.format(" -H 'X-Microsoft-OutputFormat: %s' \\\n", self.format) )
		   fp:write( " -H 'Content-Type: application/ssml+xml' \\\n" )
		   -- fp:write( string.format(" -H 'Content-Length: %d'", #payload) -- curl does it correctly
		   fp:write( string.format(" -d '%s' \\\n", payload ) )
		   fp:write( string.format(" 'https://%s/cognitiveservices/v1'\n", host) )
		   fp:close()
		   local rst = os.execute( "sh " .. destFile .. "-curl.sh" )
			if rst ~= 0 then
				fp = io.open(destFile .. "-curl.sh", "r")
				local req = fp:read("*a")
				fp:close()
				error("curl request failed (exit status %2): %1", req, rst)
				if tries == 1 then
					-- Fail on first attempt will retry with a new token
					debug("AzureTTSEngine:say() arming for new token and retry")
					self.lastToken = 0
				else
					return nil, "curl request failed"
				end
			else
				fp = io.open( destFile, "rb" )
				if fp then
					local size = fp:seek("end") or 0
					fp:close()
					if not DEBUG_MODE then os.remove(destFile .. "-curl.sh") end
					debug("AzureTTSEngine:say() received %1 byte response via curl", size)
					if size > 0 then
						-- Convert bitrate in Kbps to Bps, and from that compute clip duration (aggressive rounding up)
						return math.ceil( size / ( self.bitrate * 128 ) ) + 1, nil, size
					end
				end
				return nil, "received zero-length file"
			end
		else
			local fp,ferr = io.open(destFile, "wb")
			if not fp then error("Unable to open "..tostring(destFile)..": "..tostring(ferr)) end
			http.TIMEOUT = engineOptions.timeout or self.optionMeta.timeout.default or 15
			local req = {
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
					source = ltn12.source.string(payload),
					protocol = "any"
			}
			local r, statusMsg, h, e = https.request( req )
			debug("AzureTTSEngine:say() response %1, %2, %3, %4", r, statusMsg, h, e)
			if io.type(fp) == "file" then fp:close() end
			if statusMsg == 200 then
				fp = io.open( destFile, "rb" )
				local size = fp:seek("end") or 0
				fp:close()
				debug("AzureTTSEngine:say() received %1 byte response via socket.http", size)
				if size > 0 then
					-- Convert bitrate in Kbps to Bps, and from that compute clip duration (aggressive rounding up)
					return math.ceil( size / ( self.bitrate * 128 ) ) + 1, nil, size
				end
				return nil, "received zero-length file"
			elseif statusMsg == 401 then
				-- Authorization error; assume token has expired. Arm to re-request.
				debug("AzureTTSEngine:say() auth fail, arming for retry")
				self.lastToken = 0
			else
				warning("AzureTTSEngine:say() conversion request failed, "..tostring(statusMsg))
				warning("AzureTTSEngine:say() r="..tostring(r))
				warning("AzureTTSEngine:say() h="..tostring(h))
				warning("AzureTTSEngine:say() h=%1", h)
				warning("AzureTTSEngine:say() e="..tostring(e))
				warning("AzureTTSEngine:say() payload=%1", payload)
				fp = io.open( destFile, "r" )
				while fp do
					local s = fp:read("*l")
					if s then warning(s) else fp:close() break end
				end
				self.lastToken = 0
				return nil, "request failed "..tostring(statusMsg)
			end
		end
	end
	warning("AzureTTSEngine:say() authorization failed with Azure service")
	return nil, "authorization failed"
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
	ident = ident or "MARY"
	if not engines[ident] then base.error("Invalid/unregistered engine "..ident) end
	defaultEngine = ident
end

function getDefaultEngineId()
	return defaultEngine
end

function getDefaultLanguage( engineid )
	return engines[engineid or defaultEngine].lang
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
function generate(engine, text, destFile, engineOptions)
	-- Convert text to speech using specified engine
	engine = engine or engines[defaultEngine]
	engineOptions = engineOptions or {}
	if not (engine and engine.say) then
		return nil, "Invalid engine"
	else
		debug("generate() engine "..tostring(engine.title).." text "..tostring(text).." file "..tostring(destFile))
		local duration,err = engine:say( text, destFile, engineOptions )
		if not duration then
			warning("(tts) engine " .. (engine.title or "title?") .. " error: " .. tostring(err))
			return nil, err
		end
		return duration
	end
end

--[[ ************************ LEGACY/DEPRECATED FUNCTIONS ********************** ]]

function ConvertTTS(text, destFile, language, engineId, engineOptions)
	engineId = engineId or defaultEngine
	local engine = engines[engineId]
	engineOptions.lang = language or engineOptions.language or (engine.optionMeta.lang or {}).default or engine.lang
	return generate(engines[engineId or defaultEngine], text, destFile, engineOptions)
end

function setup(language, engine, googleUrl, osxUrl, maryUrl, rvURL, clientId, clientSecret, option) -- luacheck: ignore 212
	defaultEngine = engine or "MARY"
end
