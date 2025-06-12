# video-merge-script

🎞 视频分组合并脚本

## 使用方法

1.安装ffmpeg

```
# linux
sudo apt install ffmpeg
sudo dnf install ffmpeg

# windows
winget install Gyan.FFmpeg
```

2.建立以下目录结构

```
├── merge.sh
├── input
      ├── 1.mp4
      ├── 2.mp4
      ···
      ├── 100.mp4
├── output
```

脚本文件夹内建立input和output文件夹，将需要处理的视频放入input文件夹内，运行merge.sh（windows系统运行merge.bat）
