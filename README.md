# Aegisub Karaoke Automation Toolkit
# Aegisub 卡拉OK 自动化工具集

这是一个为 Aegisub 设计的自动化工作流项目，旨在极大地简化日语歌曲卡拉OK字幕的制作过程。
本项目包含两个核心组件，分别对应卡拉OK制作的两个关键步骤：**自动注音** 和 **样式分配预处理**。

## ✨ 主要功能 (Features)

### 1. 离线自动日语注音 (Offline Auto Furigana)
- **脚本名称**: `OneClickRuby_Offline.lua`
- **功能**: 第一步。自动识别日语汉字并为其添加假名注音。
- **特点**:
  - **完全离线**: 基于本地 Python 环境和 `fugashi` 库，无需网络，速度快且无 API 限制。
  - **智能分词**: 使用 MeCab (via fugashi) 引擎，注音准确率高。
  - **K轴支持**: 智能保留原有的卡拉OK时间轴 tags (`\k`)。

### 2. 智能样式分配与预处理 (Smart Style Assigner)
- **脚本名称**: `Smart Karaoke Preprocessor.lua`
- **功能**: 第二步。根据做好的注音轴，自动进行样式分配和标签预处理。
- **特点**:
  - **自动交替样式**: 自动将奇数行设为 `K2` 样式，偶数行设为 `K1` 样式（符合常见的双行卡拉OK模板需求）。
  - **添加模板标签**: 自动在行首添加 `{\-A}` 保留标签，为后续应用 Nudge 或其他卡拉OK模板脚本做好准备。

---

## 🛠️ 安装指南 (Installation)

### 前置要求 (Prerequisites)
1.  **Aegisub**: 已安装 Aegisub 字幕制作软件。
2.  **Python 3**: 系统中已安装 Python 3.x 环境，且已将 `python` 添加到系统环境变量 PATH 中。

### 第一步：安装 Python 依赖
打开命令提示符 (CMD) 或 PowerShell，运行以下命令安装必要的自然语言处理库：

```bash
pip install fugashi unidic-lite
```

> **注意**: `fugashi` 是一个 Python 的 MeCab 包装器，`unidic-lite` 是轻量级词典。如果不安装词典，注音将无法工作。

### 第二步：部署脚本文件
请将本目录下的以下三个文件复制到你的 Aegisub 自动化脚本目录中：

1.  `OneClickRuby_Offline.lua`
2.  `Smart Karaoke Preprocessor.lua`
3.  `furigana_local.py`

**Aegisub 自动化目录通常位于：**
- **Windows (安装版)**: `C:\Program Files\Aegisub\automation\autoload\`
- **Windows (便携版/配置文件夹)**: `%APPDATA%\Aegisub\automation\autoload\`

> **⚠️ 重要提示**: 
> `OneClickRuby_Offline.lua` 中默认硬编码了 Python 脚本路径为 `C:\Program Files\Aegisub\automation\autoload\furigana_local.py`。
> 
> **如果你将文件放在了其他位置（例如 AppData 目录），请务必用文本编辑器打开 `OneClickRuby_Offline.lua`，找到第 18 行：**
> ```lua
> local PYTHON_SCRIPT_PATH = "C:\\Program Files\\Aegisub\\automation\\autoload\\furigana_local.py"
> ```
> **将其修改为你实际存放 `furigana_local.py` 的绝对路径。**

---

## 🚀 使用方法 (Usage)

### Step 1: 自动注音
1.  在 Aegisub 中打开你的字幕文件。
2.  选中包含日语汉字的字幕行。
3.  在菜单栏点击 **Automation (自动化)** -> **一键为日语汉字注音(##汉字|<假名##)**。
    - *脚本会自动调用后台 Python 进程进行分词和注音，完成后即可看到效果。*

### Step 2: 样式分配与预处理
1.  完成注音后，选中这些字幕行。
2.  在菜单栏点击 **Automation (自动化)** -> **转换：K轴 -> 注音轴**。
3.  脚本将执行以下操作：
    - 奇数行样式变更为 `K2`。
    - 偶数行样式变更为 `K1`。
    - 行首添加 `{\-A}` 标签。

---

## ⚙️ 配置 (Configuration)

如果你需要修改 Python 解释器的路径（例如使用虚拟环境），请编辑 `OneClickRuby_Offline.lua` 的第 19 行：

```lua
local PYTHON_EXE = "python" -- 可以修改为具体的 python.exe 路径，如 "D:\\env\\Scripts\\python.exe"
```

## 📝 常见问题 (FAQ)

**Q: 运行注音脚本没有任何反应或报错？**
A: 
1. 请检查是否安装了 `fugashi` 和 `unidic-lite` (`pip list` 查看)。
2. 请检查 `OneClickRuby_Offline.lua` 中的 `PYTHON_SCRIPT_PATH` 是否指向了正确的 `furigana_local.py` 位置。
3. 可以在 Aegisub 的日志窗口查看具体的错误信息。

**Q: 注音不准确？**
A: `fugashi` 使用这一标准词典，通常准确率很高。如果是生僻人名或特殊读音，建议手动修正。

---

**Author**: 我, Gemini  
**License**: MIT
