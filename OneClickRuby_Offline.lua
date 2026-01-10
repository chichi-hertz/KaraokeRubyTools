script_name = "One Click Ruby V3 (Tag Only)"
script_description = "Add furigana tags (##Kanji|<Kana##) using local Python + fugashi"
script_author = "domo (modified for fugashi)"
ruby_part_from = "Kage Maboroshi&KiNen"
script_version = "3.2-SpaceFix"

require "karaskel"
local ffi = require"ffi"
local utf8 = require"utf8"
local json = require"json"

--Separators--
char_s = "##"  -- s(tart) of ruby part
char_m = "|<"  -- m(iddle) which divides the whole part into kanji and furigana
char_e = "##"  -- e(nd) of ruby part

-- 配置：Python脚本路径
local PYTHON_SCRIPT_PATH = "C:\\Program Files\\Aegisub\\automation\\autoload\\furigana_local.py"
local PYTHON_EXE = "python"  -- 根据需要修改

-- 工具函数
local function deleteEmpty(tbl)
	for i=#tbl,1,-1 do
		if tbl[i] == "" then table.remove(tbl, i) end
	end
	return tbl
end

local function isKatakana(s)
	if not s or s == "" then return false end
	return utf8.match(s, "^[\227\130\128-\227\131\191]+$") ~= nil
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

function addK0BeforeText(s)
	local result = ""
	local i = 1
	while i <= utf8.len(s) do
		local charC = utf8.sub(s, i, i)
		if charC == "{" then
			local j = i
			while utf8.sub(s, j, j) ~= "}" and j <= utf8.len(s) do
				j = j + 1
			end
			result = result .. utf8.sub(s, i, j)
			i = j + 1
		else
			if i == 1 or utf8.sub(s, i-1, i-1) ~= "}" then
				result = result .. "{\\k0}"
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

local function send2PythonLocal(sentence)
	if not sentence or sentence == "" then return json.encode({}) end
	sentence = sentence:gsub("\r", ""):gsub("\n", "")
	local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Windows\\Temp"
	local temp_file = temp_dir .. "\\aegisub_ruby_" .. os.time() .. "_" .. math.random(10000) .. ".txt"
	local f = io.open(temp_file, "w")
	if not f then return json.encode({}) end
	f:write(sentence)
	f:close()
	
	local cmd = string.format('%s "%s" --file=%s', PYTHON_EXE, PYTHON_SCRIPT_PATH, temp_file)
	local handle = io.popen(cmd, 'r')
	if not handle then os.remove(temp_file); return json.encode({}) end
	local result = handle:read("*a")
	handle:close()
	pcall(os.remove, temp_file)
	
	if not result or result == "" then return json.encode({}) end
	return result:gsub("^%s*", ""):gsub("%s*$", "")
end

local function json2LineText(jsonStr, lineNum)
	if not jsonStr or jsonStr == "" or jsonStr == "[]" then return "" end
	local success, decoded = pcall(json.decode, jsonStr)
	if not success or not decoded or decoded.error then return "" end
	
	local lineText = ""
	for i=1, #decoded do
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

-- !!! 重点修复的函数 !!!
local function KaraText(newText, lineKara)
	local rubyTbl = deleteEmpty(Split(newText, char_s))
	local newRubyTbl = {}
	
	-- 拆分注音块和普通字符
	for i=1, #rubyTbl do
		if string.find(rubyTbl[i], escapeLuaPattern(char_m)) then
			newRubyTbl[#newRubyTbl+1] = rubyTbl[i]
		else 
			for j=1, utf8.len(rubyTbl[i]) do
				newRubyTbl[#newRubyTbl+1] = utf8.sub(rubyTbl[i], j, j)
			end
		end
	end
	
	-- 倒序合并逻辑（修复时间轴对应多个字符的情况）
	local sylNum = #lineKara
	for i=#newRubyTbl, 2, -1 do
		local realWord = string.match(newRubyTbl[i], "([^|<]+)[<|]?")
		if sylNum > 0 and realWord and utf8.len(realWord) < utf8.len(lineKara[sylNum].sylText) then
			newRubyTbl[i-1] = newRubyTbl[i-1] .. newRubyTbl[i]
			table.remove(newRubyTbl, i)
		else
			sylNum = sylNum - 1
		end
	end
	
	local tmpSylText = ""
	local tmpSylKDur = 0
	local newKaraText = ""
	
	-- 主循环：同时遍历Kara和文本
	while #lineKara > 0 or tmpSylText ~= "" do
		-- 如果还有Kara音节，取出一个累加
		if #lineKara > 0 then
			tmpSylText = tmpSylText .. lineKara[1].sylText
			tmpSylKDur = tmpSylKDur + lineKara[1].kDur
			table.remove(lineKara, 1)
		end
		
		-- 如果注音表还有内容，尝试匹配
		if #newRubyTbl > 0 then
			local currentRubyItem = newRubyTbl[1]
			local realWord = string.match(currentRubyItem, "([^|<]+)[<|]?")
			
			-- 情况1：完全匹配
			if tmpSylText == realWord then
				newKaraText = newKaraText .. string.format("{\\k%d}%s", tmpSylKDur, currentRubyItem)
				table.remove(newRubyTbl, 1)
				tmpSylText = ""
				tmpSylKDur = 0
				
			-- 情况2 [修复关键]：Kara是空格，但注音表当前词不是空格（说明Python把空格吞了）
			-- 此时我们输出空格，但不消耗注音表里的词
			elseif tmpSylText:match("^%s+$") and not (realWord and realWord:match("^%s+$")) then
				newKaraText = newKaraText .. string.format("{\\k%d}%s", tmpSylKDur, tmpSylText)
				tmpSylText = ""
				tmpSylKDur = 0
			end
		else
			-- 情况3：注音表空了，把剩下的Kara文本全吐出来
			if tmpSylText ~= "" then
				newKaraText = newKaraText .. string.format("{\\k%d}%s", tmpSylKDur, tmpSylText)
				tmpSylText = ""
				tmpSylKDur = 0
			end
		end
		
		-- 防死循环：如果Kara空了但tmp不为空且匹配不上，强制输出（兜底）
		if #lineKara == 0 and tmpSylText ~= "" and #newRubyTbl > 0 and tmpSylText ~= string.match(newRubyTbl[1], "([^|<]+)[<|]?") then
			newKaraText = newKaraText .. string.format("{\\k%d}%s", tmpSylKDur, tmpSylText)
			tmpSylText = ""
		end
	end
	
	return newKaraText
end

function oneClickRuby(subtitles, selected_lines)
	local dialogue_start = 1
	for i=1, #subtitles do
		if subtitles[i].class == "dialogue" then
			dialogue_start = i - 1
			break
		end
	end
	
	meta, styles = karaskel.collect_head(subtitles)
	local total_lines = #selected_lines
	
	for i=1, total_lines do
		local lineNum = tostring(selected_lines[i] - dialogue_start)
		local l = subtitles[selected_lines[i]]
		if not l then goto continue end
		
		local orgText = l.text or ""
		local text = orgText:gsub("{[^}]+}", "") -- 纯文本
		
		if text == "" or text:match("^%s*$") then goto continue end
		
		local newText = ""
		
		-- 1. 卡拉OK行处理
		if string.find(orgText, "{\\[kK]%d+}") then
			aegisub.debug.out("Processing Karaoke Line: " .. lineNum .. "\n")
			
			local tempOrgText = addK0BeforeText(l.text)
			lineKara = {}
			for kDur, sylText in string.gmatch(tempOrgText, "{\\[kK](%d+)}([^{]+)") do
				lineKara[#lineKara+1] = {sylText=sylText, kDur=kDur}
			end
			
			local success, result = pcall(send2PythonLocal, text)
			if success then
				local parsed_success, parsed_text = pcall(json2LineText, result, lineNum)
				if parsed_success and parsed_text ~= "" then
					local kara_success, kara_text = pcall(KaraText, parsed_text, lineKara)
					if kara_success then
						newText = kara_text
					else
						newText = orgText
					end
				else
					newText = orgText
				end
			else
				newText = orgText
			end

		-- 2. 已经有注音的行
		elseif string.find(text, escapeLuaPattern(char_m)) then
			newText = text

		-- 3. 普通行处理
		else
			local success, result = pcall(send2PythonLocal, text)
			if success then
				local parsed_success, parsed_text = pcall(json2LineText, result, lineNum)
				if parsed_success and parsed_text ~= "" then
					newText = parsed_text
				else
					newText = orgText
				end
			else
				newText = orgText
			end
		end
		
		if newText ~= "" and newText ~= orgText then
			l.text = newText
			subtitles[selected_lines[i]] = l
		end
		aegisub.progress.set(i / total_lines * 100)
		::continue::
	end
	aegisub.set_undo_point(script_name)
end

aegisub.register_macro(script_name, script_description, oneClickRuby)