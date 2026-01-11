script_name = "自动分配K1/K2样式"
script_description = "自动分配K1/K2样式并添加保留标签，适配卡拉OK模板"
script_author = "Gemini"
script_version = "1.0"

function convert_k_to_template_ready(subtitles, selected_lines)
    -- 这是一个计数器，用于判断奇偶行
    local dialogue_counter = 0
    
    -- 遍历所有字幕行
    for i = 1, #subtitles do
        local line = subtitles[i]
        
        -- 只处理对话行 (class == "dialogue")
        if line.class == "dialogue" then
            dialogue_counter = dialogue_counter + 1
            
            -- 逻辑1：识别并应用样式 K1/K2
            -- 根据你的样本，第1行是K2，第2行是K1。
            -- 数学逻辑：奇数行(1,3,5) -> K2, 偶数行(2,4,6) -> K1
            if dialogue_counter % 2 == 1 then
                line.style = "K2"
            else
                line.style = "K1"
            end
            
            -- 逻辑2：添加 {\-A} 标签
            -- 检查行首是否已经有 {\-A}，没有则添加
            if not line.text:match("^{\\-A}") then
                -- 如果行首已经有其他tag (例如 {\k20})，插入到里面
                if line.text:match("^{") then
                    line.text = line.text:gsub("^{", "{\\-A")
                else
                    -- 如果没有tag，直接加在最前面
                    line.text = "{\\-A}" .. line.text
                end
            end
            
            -- 将修改后的行写回字幕对象
            subtitles[i] = line
        end
    end
    
    -- 创建这一步的撤销点
    aegisub.set_undo_point("K轴转注音轴")
end

-- 注册脚本菜单
aegisub.register_macro("转换：K轴 -> 注音轴", "自动分配样式并添加模板标记", convert_k_to_template_ready)