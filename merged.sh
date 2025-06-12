#!/bin/bash

# 设置当前目录为脚本所在目录并增加错误处理
cd "$(dirname "$0")" || { echo "致命错误: 无法切换到脚本目录"; exit 1; }

# 配置输入输出目录
input_dir="input"
output_dir="output"

# 创建目录结构
mkdir -p "$input_dir" "$output_dir"

echo "====== Video Merging Script (Supports FLV) ======"
echo "Parent Directory: $(pwd)"
echo "Input Directory: $input_dir"
echo "Output Directory: $output_dir"
echo

# 合并视频组函数
merge_group() {
    local group_id=$1
    shift
    local files=("$@")
    
    # 生成带时间戳的唯一临时文件
    local list_file=$(mktemp)
    local output_file="$output_dir/merged_$group_id.mp4"
    
    # 创建FFmpeg输入列表（带路径转义）
    echo -n > "$list_file"
    for file in "${files[@]}"; do
        # 转义文件路径中的单引号
        escaped_path=$(printf "%s" "$file" | sed "s/'/'\\\\''/g")
        echo "file '$escaped_path'" >> "$list_file"
    done
    
    # 获取文件数量
    local file_count_in_group=${#files[@]}
    
    echo
    echo "=== Merging Group $group_id ==="
    echo "Files in group: $file_count_in_group"
    if [ "$last_width" != "unknown" ]; then
        echo "Resolution: $last_width x $last_height"
    else
        echo "Resolution: Unknown"
    fi
    
    # 执行合并
    echo "Executing merge command..."
    ffmpeg -f concat -safe 0 -i "$list_file" -c copy "$output_file" -y
    
    if [ $? -ne 0 ]; then
        echo "! Merge failed for group $group_id, attempting alternative method..."
        
        # 尝试直接合并（使用完整路径+转义）
        local alt_output_file="$output_dir/merged_alt_$group_id.mp4"
        echo "Trying direct file merge with full paths..."
        
        # 构建带转义的文件列表字符串
        local files_str=""
        for file in "${files[@]}"; do
            escaped_path=$(printf "%s" "$file" | sed "s/'/'\\\\''/g")
            files_str+="file '$escaped_path'|"
        done
        files_str=${files_str%|}  # 移除末尾多余符号
        
        ffmpeg -f concat -safe 0 -i "$files_str" -c copy "$alt_output_file" -y
    fi
    
    # 清理临时文件
    rm -f "$list_file"
}

# 获取按名称排序的视频文件列表（支持大小写扩展名）
file_list=$(mktemp)

# 修复后的 find 命令（使用单引号包裹括号）
find "$input_dir" -maxdepth 1 -type f '(' \
    -iname "*.mp4" -o \
    -iname "*.mov" -o \
    -iname "*.mkv" -o \
    -iname "*.flv" ')' -print0 | sort -z > "$file_list"

# 检查是否有视频文件
if [ ! -s "$file_list" ]; then
    echo "Error: No video files found in $input_dir"
    echo "Supported formats: MP4, MOV, MKV, FLV"
    exit 1
fi

# 初始化变量
file_count=0
group_count=0
current_group=()
last_width=""
last_height=""

# 读取文件列表
while IFS= read -r -d '' file; do
    # 使用readlink生成规范化的绝对路径
    full_path="$(readlink -f "$file")"
    
    # 验证文件存在性
    if [ ! -f "$full_path" ]; then
        echo "Error: File not found - $full_path"
        continue
    fi
    
    # 获取纯文件名
    filename=$(basename "$file")
    
    echo "Processing: $filename"
    echo "Full path: $full_path"
    
    # 获取当前文件分辨率
    current_width=""
    current_height=""
    
    # 先尝试通过流获取分辨率
    readarray -t stream_info < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$full_path" 2>/dev/null)
    if [[ ${#stream_info[@]} -gt 0 ]]; then
        IFS=',' read -r current_width current_height <<< "${stream_info[0]}"
    fi
    
    # 如果未获取到分辨率，尝试通过格式信息获取
    if [ -z "$current_width" ] || [ -z "$current_height" ]; then
        readarray -t format_info < <(ffprobe -v error -show_entries format=width,height -of csv=p=0 "$full_path" 2>/dev/null)
        if [[ ${#format_info[@]} -gt 0 ]]; then
            IFS=',' read -r current_width current_height <<< "${format_info[0]}"
        fi
    fi
    
    # 处理分辨率获取失败的情况
    if [ -z "$current_width" ]; then
        current_width="unknown"
        echo "Warning: Resolution detection failed"
    fi
    if [ -z "$current_height" ]; then
        current_height="unknown"
    fi
    
    ((file_count++))
    
    # 分组逻辑
    if [ -n "$last_width" ]; then
        if [ "$current_width$current_height" == "$last_width$last_height" ]; then
            # 相同分辨率，添加到当前组
            current_group+=("$full_path")
        else
            # 分辨率变化，合并当前组
            if [ ${#current_group[@]} -gt 0 ]; then
                ((group_count++))
                merge_group "$group_count" "${current_group[@]}"
            fi
            # 开始新组
            current_group=("$full_path")
            last_width="$current_width"
            last_height="$current_height"
        fi
    else
        # 第一个文件
        current_group=("$full_path")
        last_width="$current_width"
        last_height="$current_height"
    fi

done < "$file_list"

# 处理最后一组
if [ ${#current_group[@]} -gt 0 ]; then
    ((group_count++))
    merge_group "$group_count" "${current_group[@]}"
fi

# 清理临时文件
rm -f "$file_list"

echo
echo "====== Processing Completed ======"
echo "Total Files Found: $file_count"
echo "Groups Created: $group_count"
echo "Output Directory: $output_dir"
echo

echo "Press any key to exit..."
read -n 1 -s