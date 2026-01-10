# -*- coding: utf-8 -*-
import sys
import json
import traceback
import os

try:
    import fugashi
    FUGASHI_AVAILABLE = True
except ImportError:
    FUGASHI_AVAILABLE = False

def kata_to_hira(kata):
    """片假名转平假名"""
    if not kata:
        return ""
    result = ""
    for char in kata:
        code = ord(char)
        if 0x30A1 <= code <= 0x30F6:  # 片假名范围
            result += chr(code - 0x60)
        else:
            result += char
    return result

def has_kanji(text):
    """检查文本是否包含汉字"""
    if not text:
        return False
    return any('\u4e00' <= c <= '\u9fff' for c in text)

def split_okurigana(surface, reading):
    """
    分离汉字词汇中的送假名
    """
    if not surface or not reading:
        return [{"surface": surface, "furigana": reading}]
    
    if surface == reading:
        return [{"surface": surface, "furigana": reading}]

    # 从末尾开始匹配相同的字符（送假名）
    s_len = len(surface)
    r_len = len(reading)
    match_count = 0
    
    while match_count < s_len and match_count < r_len:
        s_char = surface[s_len - 1 - match_count]
        r_char = reading[r_len - 1 - match_count]
        
        if s_char == r_char:
            match_count += 1
        else:
            break
    
    # 如果没有匹配的后缀，直接返回原词
    if match_count == 0:
         return [{"surface": surface, "furigana": reading}]
         
    # 切分根词和送假名
    root_s = surface[:s_len - match_count]
    root_r = reading[:r_len - match_count]
    
    suffix = surface[s_len - match_count:]
    
    res = []
    # 添加汉字部分
    if root_s:
        res.append({"surface": root_s, "furigana": root_r})
    
    # 把送假名部分拆成单字
    for char in suffix:
        res.append({"surface": char, "furigana": char})
        
    return res

def get_furigana(text):
    """获取日语文本的假名注音"""
    try:
        if not FUGASHI_AVAILABLE:
            return json.dumps({"error": "fugashi not installed"}, ensure_ascii=False)
        
        # 不要在这里 strip()，否则会丢失行首行尾的空格，导致卡拉OK对应不上
        if text is None:
             return json.dumps([], ensure_ascii=False)
        if text == "":
             return json.dumps([], ensure_ascii=False)
        
        tagger = fugashi.Tagger()
        result = []
        
        for word in tagger(text):
            surface = word.surface
            
            # 【重要修改】不要跳过空白！Aegisub 的音节里包含空格，必须保留以保持对齐。
            # fugashi 通常会把空格作为一个单独的 token 返回
            if not surface:
                continue
            
            # 判断是否需要注音
            if has_kanji(surface) and word.feature.kana:
                furigana = kata_to_hira(word.feature.kana)
                # 使用送假名分离逻辑
                split_results = split_okurigana(surface, furigana)
                result.extend(split_results)
            else:
                # 假名、英文、符号、空格等直接使用原文
                furigana = surface
                result.append({
                    "surface": surface,
                    "furigana": furigana
                })
        
        return json.dumps(result, ensure_ascii=False)
        
    except Exception as e:
        error_msg = {
            "error": str(e),
            "traceback": traceback.format_exc()
        }
        return json.dumps(error_msg, ensure_ascii=False)

if __name__ == "__main__":
    try:
        # 设置输出编码为UTF-8
        if sys.version_info[0] >= 3:
            sys.stdout.reconfigure(encoding='utf-8')
        
        # 支持两种模式：命令行参数 或 临时文件
        if len(sys.argv) > 1:
            if sys.argv[1].startswith("--file="):
                file_path = sys.argv[1][7:]
                if os.path.exists(file_path):
                    with open(file_path, 'r', encoding='utf-8') as f:
                        # 不要 strip() 整个文件内容，防止丢失首尾空格
                        text = f.read()
                    try:
                        os.remove(file_path)
                    except:
                        pass
                else:
                    text = ""
            else:
                text = sys.argv[1]
            
            output = get_furigana(text)
            sys.stdout.write(output)
            sys.stdout.flush()
        else:
            sys.stdout.write(json.dumps({"error": "No input text"}, ensure_ascii=False))
            sys.stdout.flush()
            
    except Exception as e:
        error_output = json.dumps({"error": str(e)}, ensure_ascii=False)
        sys.stdout.write(error_output)
        sys.stdout.flush()
    finally:
        sys.exit(0)