script_name = "One Click Ruby V3"
script_description = "Get the formatted lyrics with furigana using local Python + fugashi"
script_author = "domo (modified for fugashi)"
ruby_part_from = "Kage Maboroshi&KiNen"
script_version = "3.0"

require "karaskel"
local ffi = require"ffi"
local utf8 = require"utf8"
local json = require"json"

meta = nil
styles = nil

--Typesetting Parameters--
rubypadding = 0 --extra spacing of ruby chars
rubyscale = 0.5 --scale of ruby chars 

--Separators--
char_s = "##"  -- s(tart) of ruby part
char_m = "|<"  -- m(iddle) which divides the whole part into kanji and furigana
char_e = "##"  -- e(nd) of ruby part

-- 配置：Python脚本路径
local PYTHON_SCRIPT_PATH = "C:\\Program Files\\Aegisub\\automation\\autoload\\furigana_local.py"

-- 如果需要指定Python路径，修改这里
local PYTHON_EXE = "python"  -- 或者 "python3" 或完整路径 "C:\\Python39\\python.exe"


local function deleteEmpty(tbl)
	for i=#tbl,1,-1 do
		if tbl[i] == "" then
			table.remove(tbl, i)
		end
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
	-- Escape special characters for Lua patterns
	return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

local function escapeShellArg(str)
	-- Windows shell escaping
	-- Replace " with ""  and wrap in quotes
	str = str:gsub('"', '""')
	return '"' .. str .. '"'
end

local function send2PythonLocal(sentence)
	if not sentence or sentence == "" then
		aegisub.debug.out("WARNING: Empty sentence sent to Python\n")
		return json.encode({})
	end
	
	-- 移除可能导致问题的特殊字符
	sentence = sentence:gsub("\r", ""):gsub("\n", "")
	
	-- 使用临时文件传递文本，避免命令行转义问题
	local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Windows\\Temp"
	local temp_file = temp_dir .. "\\aegisub_ruby_" .. os.time() .. "_" .. math.random(10000) .. ".txt"
	
	-- 写入临时文件
	local f = io.open(temp_file, "w")
	if not f then
		aegisub.debug.out("ERROR: Cannot create temp file: " .. temp_file .. "\n")
		return json.encode({})
	end
	f:write(sentence)
	f:close()
	
	-- 构建命令
	local cmd = string.format('%s "%s" --file=%s', PYTHON_EXE, PYTHON_SCRIPT_PATH, temp_file)
	
	aegisub.debug.out("DEBUG: Running command for text: " .. sentence .. "\n")
	
	local handle = io.popen(cmd, 'r')
	if not handle then 
		aegisub.debug.out("ERROR: Failed to execute Python script\n")
		-- 清理临时文件
		os.remove(temp_file)
		return json.encode({})
	end
	
	local result = handle:read("*a")
	local close_success = handle:close()
	
	-- 清理临时文件（如果Python没有删除）
	pcall(os.remove, temp_file)
	
	if not result or result == "" then
		aegisub.debug.out("ERROR: Empty response from Python\n")
		return json.encode({})
	end
	
	-- 清理输出
	result = result:gsub("^%s*", ""):gsub("%s*$", "")
	
	aegisub.debug.out("DEBUG: Python Output: " .. result .. "\n")
	
	return result
end


local function json2LineText(jsonStr, lineNum)
	if not jsonStr or jsonStr == "" or jsonStr == "[]" then
		aegisub.debug.out("WARNING: Empty JSON for line " .. lineNum .. "\n")
		return ""
	end
	
	local success, decoded = pcall(json.decode, jsonStr)
	
	if not success then 
		aegisub.debug.out("ERROR: Failed to decode JSON for line " .. lineNum .. "\n")
		aegisub.debug.out("JSON was: " .. jsonStr .. "\n")
		return "" 
	end
	
	if not decoded then 
		aegisub.debug.out("ERROR: Decoded result is nil for line " .. lineNum .. "\n")
		return "" 
	end
	
	if decoded.error then 
		aegisub.debug.out("ERROR from Python script: " .. tostring(decoded.error) .. "\n")
		if decoded.traceback then
			aegisub.debug.out("Traceback: " .. tostring(decoded.traceback) .. "\n")
		end
		return "" 
	end
	
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

local function KaraText(newText, lineKara)
	rubyTbl = deleteEmpty(Split(newText, char_s))
	newRubyTbl = {}
	
	for i=1, #rubyTbl do
		if string.find(rubyTbl[i], escapeLuaPattern(char_m)) then
			newRubyTbl[#newRubyTbl+1] = rubyTbl[i]
		else 
			for j=1, utf8.len(rubyTbl[i]) do
				newRubyTbl[#newRubyTbl+1] = utf8.sub(rubyTbl[i], j, j)
			end
		end
	end
	
	sylNum = #lineKara
	for i=#newRubyTbl, 2, -1 do
		realWord = string.match(newRubyTbl[i], "([^|<]+)[<|]?")
		if realWord and utf8.len(realWord) < utf8.len(lineKara[sylNum].sylText) then
			newRubyTbl[i-1] = newRubyTbl[i-1] .. newRubyTbl[i]
			table.remove(newRubyTbl, i)
		else
			sylNum = sylNum - 1
		end
	end
	
	tmpSylText = ""
	tmpSylKDur = 0
	i = 1
	newKaraText = ""
	
	while i <= #lineKara do
		tmpSylText = tmpSylText .. lineKara[i].sylText
		tmpSylKDur = tmpSylKDur + lineKara[i].kDur
		table.remove(lineKara, 1)
		realWord = string.match(newRubyTbl[i], "([^|<]+)[<|]?")
		
		if tmpSylText == realWord then
			newKaraText = newKaraText .. string.format("{\\k%d}%s", tmpSylKDur, newRubyTbl[i])
			table.remove(newRubyTbl, i)
			tmpSylText = ""
			tmpSylKDur = 0
		end
	end
	
	return newKaraText
end

local function parse_templates(meta, styles, subs)
	local i = 1
	while i <= #subs do
		aegisub.progress.set((i-1) / #subs * 100)
		local l = subs[i]
		i = i + 1
		if l.class == "dialogue" and l.effect == "furi-fx" then
			i = i - 1
			subs.delete(i)
		end
	end
	aegisub.progress.set(100)
end

local function processline(subs, line, li)
	line.comment = false
	local originline = table.copy(line)
	
	local ktag = "{\\k0}"
	local stylefs = styles[line.style].fontsize
	local rubbyfs = stylefs * rubyscale
	
	if string.find(line.text, escapeLuaPattern(char_s) .. "(.-)" .. escapeLuaPattern(char_m) .. "(.-)" .. escapeLuaPattern(char_e)) ~= nil then
		if (char_s == "(" and char_m == "," and char_e == ")") then
			line.text = string.gsub(line.text, "%((.-),(.-)%)", ktag.."%1".."|".."%2"..ktag)
		elseif (char_s == "" and char_m == "(" and char_e == ")") then
			line.text = string.gsub(line.text, "(^[ぁ-ゖ]+)%(([ぁ-ゖ]+)%)^[ぁ-ゖ]+", ktag.."%1".."|".."%2"..ktag)
		else
			line.text = string.gsub(line.text, escapeLuaPattern(char_s) .. "(.-)" .. escapeLuaPattern(char_m) .. "(.-)" .. escapeLuaPattern(char_e), ktag.."%1".."|".."%2"..ktag)
		end
	
		local vl = table.copy(line)
		karaskel.preproc_line(subs, meta, styles, vl)
	
		if (char_s == "(" and char_m == "," and char_e == ")") then
			originline.text = string.gsub(originline.text, "%((.-),(.-)%)", "%1")
		elseif (char_s == "" and char_m == "(" and char_e == ")") then
			originline.text = string.gsub(originline.text, "(^[ぁ-ゖ]+)%(([ぁ-ゖ]+)%)", "%1")
		else
			originline.text = string.gsub(originline.text, escapeLuaPattern(char_s) .. "(.-)" .. escapeLuaPattern(char_m) .. "(.-)" .. escapeLuaPattern(char_e), "%1")
		end
	
		originline.text = string.format("{\\pos(%d,%d)}", vl.x, vl.y) .. originline.text
		originline.effect = "furi-fx"
		subs.append(originline)

		for i = 1, vl.furi.n do
			local fl = table.copy(line)
			local rlx = vl.left + vl.kara[vl.furi[i].i].center
			local rly = vl.top - rubbyfs/2 - rubypadding
			fl.text = string.format("{\\an5\\fs%d\\pos(%d,%d)}%s", rubbyfs, rlx, rly, vl.furi[i].text)
			fl.effect = "furi-fx"
			subs.append(fl)
		end
	else
		subs.append(originline)
	end
end

local function Ruby(subs, sel)
	meta, styles = karaskel.collect_head(subs)
	for i=1, #sel do
		processline(subs, sel[i], i)
	end
	aegisub.set_undo_point(script_name) 
end

function oneClickRuby(subtitles, selected_lines)
	-- 查找对话开始位置
	local dialogue_start = 1
	for i=1, #subtitles do
		if subtitles[i].class == "dialogue" then
			dialogue_start = i - 1
			break
		end
	end
	
	-- 收集样式信息
	meta, styles = karaskel.collect_head(subtitles)
	
	newLineTbl = {}
	local total_lines = #selected_lines
	
	aegisub.debug.out("=== Starting Ruby Processing ===\n")
	aegisub.debug.out("Total lines to process: " .. total_lines .. "\n\n")
	
	for i=1, total_lines do
		local lineNum = tostring(selected_lines[i] - dialogue_start)
		local l = subtitles[selected_lines[i]]
		
		if not l then
			aegisub.debug.out("ERROR: Line " .. lineNum .. " is nil, skipping\n")
			goto continue
		end
		
		local orgText = l.text or ""
		
		aegisub.debug.out("--- Processing Line " .. lineNum .. " (" .. i .. "/" .. total_lines .. ") ---\n")
		
		-- 注释原始行
		l.comment = true
		subtitles[selected_lines[i]] = l
		
		-- 移除所有标签以获取纯文本
		local text = orgText:gsub("{[^}]+}", "")
		
		-- 跳过空行
		if text == "" or text:match("^%s*$") then
			aegisub.debug.out("Line " .. lineNum .. " is empty, skipping\n\n")
			goto continue
		end
		
		local newText = ""
		
		-- 检查是否是卡拉OK行
		if string.find(orgText, "{\\[kK]%d+}") then
			aegisub.debug.out("Processing line " .. lineNum .. " as KARAOKE line.\n")
			
			orgText = addK0BeforeText(l.text)
			if orgText ~= l.text then 
				aegisub.debug.out("[WARNING] {\\k0} was generated for syllable with multiple characters.\n")
			end
			
			lineKara = {}
			for kDur, sylText in string.gmatch(orgText, "{\\[kK](%d+)}([^{]+)") do
				lineKara[#lineKara+1] = {sylText=sylText, kDur=kDur}
			end
			
			aegisub.progress.task("Requesting for line: " .. lineNum)
			
			-- 调用Python处理
			local success, result = pcall(send2PythonLocal, text)
			
			if not success then
				aegisub.debug.out("ERROR calling Python for line " .. lineNum .. ": " .. tostring(result) .. "\n")
				newText = orgText
			else
				aegisub.progress.task("Parsing for line: " .. lineNum)
				
				local parsed_success, parsed_text = pcall(json2LineText, result, lineNum)
				
				if not parsed_success then
					aegisub.debug.out("ERROR parsing JSON for line " .. lineNum .. ": " .. tostring(parsed_text) .. "\n")
					newText = orgText
				elseif type(parsed_text) == "string" and parsed_text ~= "" then
					local kara_success, kara_text = pcall(KaraText, parsed_text, lineKara)
					if not kara_success then
						aegisub.debug.out("ERROR in KaraText for line " .. lineNum .. ": " .. tostring(kara_text) .. "\n")
						newText = orgText
					else
						newText = kara_text
					end
				else
					aegisub.debug.out("WARNING: Empty result for line " .. lineNum .. ", using original\n")
					newText = orgText
				end
			end
			
			l.effect = "karaoke"
			
		-- 检查是否已经有注音标记
		elseif string.find(text, escapeLuaPattern(char_m)) then
			aegisub.debug.out("Line " .. lineNum .. " already has ruby marks, using as-is.\n")
			newText = text
			l.effect = "ruby"
			
		-- 普通行，调用Python获取注音
		else
			aegisub.debug.out("Processing line " .. lineNum .. " as NORMAL line.\n")
			
			aegisub.progress.task("Requesting for line: " .. lineNum)
			
			local success, result = pcall(send2PythonLocal, text)
			
			if not success then
				aegisub.debug.out("ERROR calling Python for line " .. lineNum .. ": " .. tostring(result) .. "\n")
				newText = orgText
			else
				aegisub.progress.task("Parsing for line: " .. lineNum)
				
				local parsed_success, parsed_text = pcall(json2LineText, result, lineNum)
				
				if not parsed_success then
					aegisub.debug.out("ERROR parsing JSON for line " .. lineNum .. ": " .. tostring(parsed_text) .. "\n")
					newText = orgText
				elseif type(parsed_text) == "string" and parsed_text ~= "" then
					newText = parsed_text
				else
					aegisub.debug.out("WARNING: Empty result for line " .. lineNum .. ", using original\n")
					newText = orgText
				end
			end
			
			l.effect = "ruby"
		end
		
		-- 写入结果
		aegisub.progress.task("Writing for line: " .. lineNum)
		
		if newText ~= "" then
			l.text = newText
		else
			l.text = orgText
		end
		
		l.comment = false
		newLineTbl[#newLineTbl+1] = l
		
		aegisub.debug.out("Line " .. lineNum .. " completed successfully.\n")
		aegisub.debug.out("Result: " .. l.text .. "\n\n")
		
		-- 更新进度
		aegisub.progress.set(i / total_lines * 100)
		
		::continue::
	end
	
	aegisub.debug.out("=== Applying Ruby formatting ===\n")
	
	-- 应用Ruby格式
	local ruby_success, ruby_error = pcall(Ruby, subtitles, newLineTbl)
	
	if not ruby_success then
		aegisub.debug.out("ERROR in Ruby formatting: " .. tostring(ruby_error) .. "\n")
		aegisub.debug.out("Lines were processed but not formatted.\n")
	end
	
	aegisub.debug.out("=== All Done! ===\n")
	aegisub.set_undo_point(script_name)
end

aegisub.register_macro(script_name, script_description, oneClickRuby)

