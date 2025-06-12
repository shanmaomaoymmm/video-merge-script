@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: 设置当前目录为父目录
cd /d "%~dp0"

:: 配置输入输出目录
set "input_dir=input"
set "output_dir=output"

:: 创建目录结构
if not exist "%input_dir%" (
    echo Creating input directory: %input_dir%
    mkdir "%input_dir%"
)
if not exist "%output_dir%" (
    echo Creating output directory: %output_dir%
    mkdir "%output_dir%"
)

echo.
echo ====== Video Merging Script (Supports FLV) ======
echo Parent Directory: %cd%
echo Input Directory: %input_dir%
echo Output Directory: %output_dir%
echo.

:: 获取按名称排序的视频文件列表（包含FLV）
set "file_list=%temp%\video_files.txt"
dir /b /a-d /on "%input_dir%\*.mp4" "%input_dir%\*.mov" "%input_dir%\*.mkv" "%input_dir%\*.flv" 2>nul > "%file_list%"

:: 检查是否有视频文件
if not exist "%file_list%" (
    echo Error: No video files found in %input_dir%
    echo Supported formats: MP4, MOV, MKV, FLV
    goto end
)

:: 初始化变量
set /a file_count=0
set /a group_count=0
set "current_group="
set "last_width="
set "last_height="

:: 读取文件列表
for /f "usebackq delims=" %%f in ("%file_list%") do (
    set "filename=%%f"
    
    :: 使用完整路径，避免相对路径问题
    set "full_path=%cd%\%input_dir%\%%f"
    
    echo Processing: !filename!
    
    :: 获取当前文件分辨率 - 改进FLV分辨率检测
    set "current_width="
    set "current_height="
    
    :: 先尝试通过流获取分辨率
    for /f "tokens=1-2" %%w in ('ffprobe -v error -select_streams v:0 -show_entries stream^=width^,height -of csv^=p^=0 "!full_path!" 2^>^&1') do (
        set "current_width=%%w"
        set "current_height=%%x"
    )
    
    :: 如果未获取到分辨率，尝试通过格式信息获取
    if "!current_width!.!current_height!"=="." (
        for /f "tokens=1-2" %%w in ('ffprobe -v error -show_entries format^=width^,height -of csv^=p^=0 "!full_path!" 2^>^&1') do (
            set "current_width=%%w"
            set "current_height=%%x"
        )
    )
    
    :: 处理分辨率获取失败的情况
    if "!current_width!"=="" (
        set "current_width=unknown"
        echo  Warning: Resolution detection failed
    )
    if "!current_height!"=="" set "current_height=unknown"
    
    set /a file_count+=1
    
    :: 分组逻辑
    if "!last_width!" neq "" (
        if "!current_width!x!current_height!"=="!last_width!x!last_height!" (
            :: 相同分辨率，添加到当前组
            if defined current_group (
                set "current_group=!current_group! "!full_path!""
            ) else (
                set "current_group="!full_path!""
            )
        ) else (
            :: 分辨率变化，合并当前组
            if defined current_group (
                set /a group_count+=1
                call :merge_group !group_count! "!current_group!"
            )
            :: 开始新组
            set "current_group="!full_path!""
            set "last_width=!current_width!"
            set "last_height=!current_height!"
        )
    ) else (
        :: 第一个文件
        set "current_group="!full_path!""
        set "last_width=!current_width!"
        set "last_height=!current_height!"
    )
)

:: 处理最后一组
if defined current_group (
    set /a group_count+=1
    call :merge_group !group_count! "!current_group!"
)

:: 清理临时文件
if exist "%file_list%" del "%file_list%" >nul 2>nul

echo.
echo ====== Processing Completed ======
echo Total Files Found: !file_count!
echo Groups Created: !group_count!
echo Output Directory: %output_dir%
echo.
goto end

:: 合并视频组函数 - 修复路径问题
:merge_group
setlocal
set "group_id=%~1"
set "files=%~2"
set "list_file=%temp%\concat_list_%group_id%.txt"
set "output_file=%cd%\%output_dir%\merged_%group_id%.mp4"

:: 创建FFmpeg输入列表 - 避免多余引号
echo. > "%list_file%"
for %%i in (%files%) do (
    set "file_path=%%~i"
    :: 移除路径中的引号
    set "file_path=!file_path:"=!"
    echo file '!file_path!' >> "%list_file%"
)

:: 获取文件数量
set /a file_count_in_group=0
for %%i in (%files%) do set /a file_count_in_group+=1

echo.
echo === Merging Group %group_id% ===
echo Files in group: !file_count_in_group!
if not "!last_width!"=="unknown" (
    echo Resolution: !last_width!x!last_height!
) else (
    echo Resolution: Unknown
)

:: 调试信息
echo Concat list content:
type "%list_file%"

:: 执行合并
echo Executing merge command...
ffmpeg -f concat -safe 0 -i "%list_file%" -c copy "%output_file%" -y

if errorlevel 1 (
    echo ! Merge failed for group %group_id%, attempting alternative method...
    
    :: 尝试直接使用文件列表
    set "alt_output_file=%cd%\%output_dir%\merged_alt_%group_id%.mp4"
    echo Trying direct file merge...
    ffmpeg -i "concat:!files:"=!"" -c copy "%alt_output_file%" -y
)

if errorlevel 1 (
    echo !! Critical error: Merge failed for group %group_id% !!
    echo !! You may need to re-encode the videos manually.
) else (
    echo Successfully created: %output_file%
)

:: 清理临时列表
if exist "%list_file%" del "%list_file%" >nul 2>nul
endlocal
goto :eof

:end
echo.
echo Script execution completed
echo Press any key to exit...
pause >nul
endlocal