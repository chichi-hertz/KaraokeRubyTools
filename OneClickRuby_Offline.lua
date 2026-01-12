script_name = "一键为日语汉字注音(##汉字|<假名##)"
script_description = "使用本地 Python + fugashi 添加假名注音标签 (##汉字|<假名##)"
script_author = "domo (modified for fugashi)"
ruby_part_from = "Kage Maboroshi&KiNen"
script_version = "3.4-Batch-Fixed"

require "karaskel"
local ffi = require "ffi"
local utf8 = require "utf8"
local json = require "json"

--Separators--
char_s = "##" -- s(tart) of ruby part
char_m = "|<" -- m(iddle) which divides the whole part into kanji and furigana
char_e = "##" -- e(nd) of ruby part

-- 配置：Python脚本路径
local PYTHON_SCRIPT_PATH = "C:\\Program Files\\Aegisub\\automation\\autoload\\furigana_local.py"
local PYTHON_EXE = "python" -- 根据需要修改

-- 工具函数
local function deleteEmpty(tbl)
	for i = #tbl, 1, -1 do
		if tbl[i] == "" then table.remove(tbl, i) end
	end
	return tbl
end

local function isKatakana(s)
	if not s or s == "" then return false end
	return utf8.match(s, "^[\227\130\128-\227\131\191]+$") ~= nil
end
-- 【新增】检查字符串是否包含日语字符（平假名、片假名、汉字）
local function hasJapanese(s)
	if not s or s == "" then return false end
	-- 使用字节模式匹配日语字符
	-- 平假名: \227\129\130 - \227\129\191
	-- 片假名: \227\130\128 - \227\131\191
	-- CJK汉字: 大致范围
	
	local i = 1
	while i <= #s do
		local b = s:byte(i)
		if b >= 0xE0 and b <= 0xEF then
			-- 3字节UTF-8字符
			if i + 2 <= #s then
				local b1, b2, b3 = s:byte(i, i + 2)
				-- 平假名 U+3040-U+309F: E3 81 80 - E3 82 9F
				if b1 == 0xE3 and ((b2 == 0x81 and b3 >= 0x80) or (b2 == 0x82 and b3 <= 0x9F)) then
					return true
				end
				-- 片假名 U+30A0-U+30FF: E3 82 A0 - E3 83 BF
				if b1 == 0xE3 and ((b2 == 0x82 and b3 >= 0xA0) or (b2 == 0x83 and b3 <= 0xBF)) then
					return true
				end
				-- CJK统一汉字 U+4E00-U+9FFF: E4 B8 80 - E9 BF BF
				if (b1 >= 0xE4 and b1 <= 0xE9) then
					return true
				end
			end
			i = i + 3
		elseif b >= 0xC0 and b <= 0xDF then
			i = i + 2
		elseif b >= 0xF0 then
			i = i + 4
		else
			i = i + 1
		end
	end
	return false
end


function Split(szFullString, szSeparator)
	local nFindStartIndex = 1
	local nSplitIndex = 1
	local nSplitArray = {}
	while true do
		local nFindLastIndex = string.find(szFullString, szSeparator, nFindStartIndex)
		if not nFindLastIndex then
			nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, string.len(szFullString))
			break
		end
		nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, nFindLastIndex - 1)
		nFindStartIndex = nFindLastIndex + string.len(szSeparator)
		nSplitIndex = nSplitIndex + 1
	end
	return nSplitArray
end
-- 【修改】只为日语部分添加k0标签
function addK0BeforeText(s)
	local result = ""
	local i = 1
	while i <= utf8.len(s) do
		local charC = utf8.sub(s, i, i)
		if charC == "{" then
			-- 保留原有的标签
			local j = i
			while utf8.sub(s, j, j) ~= "}" and j <= utf8.len(s) do
				j = j + 1
			end
			result = result .. utf8.sub(s, i, j)
			i = j + 1
		else
			-- 检查当前字符是否为日语字符
			local isJapaneseChar = false
			local byteStr = charC
			if #byteStr == 3 then
				local b1, b2, b3 = byteStr:byte(1, 3)
				-- 平假名 U+3040-U+309F: E3 81 80 - E3 82 9F
				if b1 == 0xE3 and ((b2 == 0x81 and b3 >= 0x80) or (b2 == 0x82 and b3 <= 0x9F)) then
					isJapaneseChar = true
				end
				-- 片假名 U+30A0-U+30FF: E3 82 A0 - E3 83 BF
				if b1 == 0xE3 and ((b2 == 0x82 and b3 >= 0xA0) or (b2 == 0x83 and b3 <= 0xBF)) then
					isJapaneseChar = true
				end
				-- CJK统一汉字 U+4E00-U+9FFF: E4 B8 80 - E9 BF BF
				if (b1 >= 0xE4 and b1 <= 0xE9) then
					isJapaneseChar = true
				end
			end
			
			if isJapaneseChar then
				-- 只为日语字符添加k0标签
				if i == 1 or utf8.sub(s, i - 1, i - 1) ~= "}" then
					result = result .. "{\\k0}"
				end
			end
			result = result .. charC
			i = i + 1
		end
	end
	return result
end


local function escapeLuaPattern(str)
	return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

-- 【批量发送所有文本到Python】
local function send2PythonBatch(texts)
	if not texts or #texts == 0 then return {} end
	
	local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Windows\\Temp"
	local timestamp = os.time()
	local random_id = math.random(100000, 999999)
	local temp_file = temp_dir .. "\\aegisub_ruby_batch_" .. timestamp .. "_" .. random_id .. ".json"
	
	-- 将所有文本打包成JSON数组
	local input_data = json.encode(texts)
	local f = io.open(temp_file, "w")
	if not f then return {} end
	f:write(input_data)
	f:close()

	local cmd = string.format('%s "%s" --batch --file=%s', PYTHON_EXE, PYTHON_SCRIPT_PATH, temp_file)
	local handle = io.popen(cmd, 'r')
	if not handle then
		pcall(os.remove, temp_file)
		return {}
	end
	
	local result = handle:read("*a")
	handle:close()
	pcall(os.remove, temp_file)

	if not result or result == "" then return {} end
	result = result:gsub("^%s*", ""):gsub("%s*$", "")
	
	-- 解析返回的JSON数组
	local success, decoded = pcall(json.decode, result)
	if not success or not decoded then return {} end
	
	return decoded
end

local function json2LineText(decoded)
	if not decoded or decoded.error then return "" end

	local lineText = ""
	for i = 1, #decoded do
		local item = decoded[i]
		if item.surface then
			if item.furigana and item.furigana ~= item.surface and not isKatakana(item.surface) then
				lineText = lineText .. char_s .. item.surface .. char_m .. item.furigana .. char_e
			else
				lineText = lineText .. item.surface
			end
		end
	end
	return lineText
end

local function KaraText(newText, lineKara)
	local rubyTbl = deleteEmpty(Split(newText, char_s))
	local newRubyTbl = {}

	-- 拆分注音块和普通字符
	for i = 1, #rubyTbl do
		if string.find(rubyTbl[i], escapeLuaPattern(char_m)) then
			newRubyTbl[#newRubyTbl + 1] = rubyTbl[i]
		else
			for j = 1, utf8.len(rubyTbl[i]) do
				newRubyTbl[#newRubyTbl + 1] = utf8.sub(rubyTbl[i], j, j)
			end
		end
	end

	-- 倒序合并逻辑（修复时间轴对应多个字符的情况）
	local sylNum = #lineKara
	for i = #newRubyTbl, 2, -1 do
		local realWord = string.match(newRubyTbl[i], "([^|<]+)[<|]?")
		if sylNum > 0 and realWord and utf8.len(realWord) < utf8.len(lineKara[sylNum].sylText) then
			newRubyTbl[i - 1] = newRubyTbl[i - 1] .. newRubyTbl[i]
			table.remove(newRubyTbl, i)
		else
			sylNum = sylNum - 1
		end
	end

	local tmpSylText = ""
	local tmpSylKDur = 0
	local tmpKType = "k"
	local newKaraText = ""

	while #lineKara > 0 or tmpSylText ~= "" do
		if #lineKara > 0 then
			tmpSylText = tmpSylText .. lineKara[1].sylText
			tmpSylKDur = tmpSylKDur + lineKara[1].kDur
			tmpKType = lineKara[1].kType
			table.remove(lineKara, 1)
		end

		if #newRubyTbl > 0 then
			local currentRubyItem = newRubyTbl[1]
			local realWord = string.match(currentRubyItem, "([^|<]+)[<|]?")

			if tmpSylText == realWord then
				newKaraText = newKaraText .. string.format("{\\%s%d}%s", tmpKType, tmpSylKDur, currentRubyItem)
				table.remove(newRubyTbl, 1)
				tmpSylText = ""
				tmpSylKDur = 0
				tmpKType = "k"
			elseif tmpSylText:match("^%s+$") and not (realWord and realWord:match("^%s+$")) then
				newKaraText = newKaraText .. string.format("{\\%s%d}%s", tmpKType, tmpSylKDur, tmpSylText)
				tmpSylText = ""
				tmpSylKDur = 0
				tmpKType = "k"
			end
		else
			if tmpSylText ~= "" then
				newKaraText = newKaraText .. string.format("{\\%s%d}%s", tmpKType, tmpSylKDur, tmpSylText)
				tmpSylText = ""
				tmpSylKDur = 0
				tmpKType = "k"
			end
		end

		if #lineKara == 0 and tmpSylText ~= "" and #newRubyTbl > 0 and tmpSylText ~= string.match(newRubyTbl[1], "([^|<]+)[<|]?") then
			newKaraText = newKaraText .. string.format("{\\%s%d}%s", tmpKType, tmpSylKDur, tmpSylText)
			tmpSylText = ""
		end
	end

	return newKaraText
end

function oneClickRuby(subtitles, selected_lines)
	local dialogue_start = 1
	for i = 1, #subtitles do
		if subtitles[i].class == "dialogue" then
			dialogue_start = i - 1
			break
		end
	end

	meta, styles = karaskel.collect_head(subtitles)
	local total_lines = #selected_lines

	-- 【关键修改】收集所有需要处理的文本，跳过纯英文行
	local texts_to_process = {}
	local line_info = {}
	
	for i = 1, total_lines do
		local l = subtitles[selected_lines[i]]
		if l then
			local orgText = l.text or ""
			local text = orgText:gsub("{[^}]+}", "")
			
			-- 【修改】只处理包含日语的行
			if text ~= "" and not text:match("^%s*$") and not string.find(text, escapeLuaPattern(char_m)) and hasJapanese(text) then
				texts_to_process[#texts_to_process + 1] = text
				line_info[#line_info + 1] = {
					index = i,
					line_num = selected_lines[i],
					org_text = orgText,
					clean_text = text,
					is_karaoke = string.find(orgText, "{\\[kK][foO]?%d+}") ~= nil
				}
			end
		end
	end
	
	-- 如果没有需要处理的行，直接返回
	if #texts_to_process == 0 then
		aegisub.debug.out("没有找到包含日语的行需要处理\n")
		return
	end
	
	-- 【批量调用Python】
	aegisub.progress.task("正在批量获取注音...")
	local results = send2PythonBatch(texts_to_process)
	
	if #results ~= #line_info then
		aegisub.debug.out("警告：Python返回结果数量不匹配\n")
	end
	
	-- 【处理返回结果】
	for i = 1, #line_info do
		local info = line_info[i]
		local l = subtitles[info.line_num]
		local newText = ""
		
		if results[i] then
			if info.is_karaoke then
				-- 卡拉OK行
				local tempOrgText = addK0BeforeText(info.org_text)
				local lineKara = {}
				for kType, kDur, sylText in string.gmatch(tempOrgText, "{\\([kK][foO]?)(%d+)}([^{]+)") do
					lineKara[#lineKara + 1] = { sylText = sylText, kDur = kDur, kType = kType }
				end
				
				local parsed_text = json2LineText(results[i])
				if parsed_text ~= "" then
					local kara_success, kara_text = pcall(KaraText, parsed_text, lineKara)
					if kara_success then
						newText = kara_text
					else
						newText = info.org_text
					end
				else
					newText = info.org_text
				end
			else
				-- 普通行
				local parsed_text = json2LineText(results[i])
				if parsed_text ~= "" then
					newText = parsed_text
				else
					newText = info.org_text
				end
			end
			
			if newText ~= "" and newText ~= info.org_text then
				l.text = newText
				subtitles[info.line_num] = l
			end
		end
		
		aegisub.progress.set(i / #line_info * 100)
	end
	
	aegisub.set_undo_point(script_name)
end

aegisub.register_macro(script_name, script_description, oneClickRuby)
