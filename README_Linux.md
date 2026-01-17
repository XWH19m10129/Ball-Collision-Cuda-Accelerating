# Linux 服务器运行指南

本文档说明如何在**无图形界面的 Linux 服务器**上编译和运行 CUDA 球体碰撞模拟程序。

## 环境要求

### 硬件要求
- NVIDIA GPU (支持 CUDA 计算能力 6.0+)
- 至少 2GB GPU 显存

### 软件要求
- Linux 操作系统 (Ubuntu 18.04+, CentOS 7+, 或其他主流发行版)
- NVIDIA GPU 驱动
- CUDA Toolkit 10.0+ (推荐 11.0+)
- GCC 编译器 (g++ 7.0+)

## 安装步骤

### 1. 检查 CUDA 环境

首先确认 CUDA 已正确安装：

```bash
nvcc --version
```

应该显示 CUDA 编译器版本信息，例如：
```
nvcc: NVIDIA (R) Cuda compiler driver
Copyright (c) 2005-2021 NVIDIA Corporation
Built on Sun_Mar_21_19:15:46_PDT_2021
Cuda compilation tools, release 11.2, V11.2.152
```

检查 GPU 状态：

```bash
nvidia-smi
```

应该显示 GPU 信息和驱动版本。

### 2. 克隆或下载项目

```bash
git clone https://github.com/XWH19m10129/Ball-Collision-Cuda-Accelerating.git
cd Ball-Collision-Cuda-Accelerating
```

### 3. 编译项目

使用 Makefile 编译：

```bash
make
```

如果编译成功，将在 `bin/` 目录下生成 `ball_collision` 可执行文件。

**注意**：如果您的 GPU 计算能力不是 6.0，需要修改 `Makefile` 中的 `-arch=sm_60` 参数。查看您的 GPU 计算能力：

```bash
nvidia-smi --query-gpu=compute_cap --format=csv
```

然后在 Makefile 中修改对应的 `sm_XX` 值。

### 4. 创建输出目录

```bash
mkdir -p output
```

### 5. 运行模拟

#### 默认运行 (1000帧)

```bash
./bin/ball_collision
```

或使用 make 命令：

```bash
make run
```

#### 指定帧数运行

```bash
./bin/ball_collision 500
```

或使用 make 命令：

```bash
make run-frames FRAMES=500
```

## 输出说明

### 输出文件格式

模拟结果保存在 `output/` 目录下，文件命名格式为 `frame_XXXXX.csv`，其中 XXXXX 是帧编号（5位数字，前导零填充）。

每个 CSV 文件包含当前帧所有球体的状态信息：

```csv
id,x,y,z,vx,vy,vz,radius,r,g,b
0,1.234,5.678,2.345,0.123,-0.045,0.234,0.35,0.8,0.2,0.5
1,2.345,6.789,3.456,0.234,-0.056,0.345,0.42,0.3,0.7,0.9
...
```

字段说明：
- `id`: 球体编号
- `x,y,z`: 球体中心位置坐标
- `vx,vy,vz`: 球体速度向量
- `radius`: 球体半径
- `r,g,b`: 球体颜色 (RGB值，范围 0.0-1.0)

### 数据保存频率

默认每隔 10 帧保存一次数据，以及最后一帧。可以在 `src/glcuda.cu` 中修改保存频率：

```cpp
// 每隔10帧保存一次数据
if (frame % 10 == 0) {
    saveFrameData(frame);
    ...
}
```

## 数据可视化

### Python 可视化示例

使用 Python 和 matplotlib 可以轻松可视化模拟结果：

```python
import pandas as pd
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D

# 读取某一帧的数据
df = pd.read_csv('output/frame_00000.csv')

# 创建3D图形
fig = plt.figure(figsize=(10, 10))
ax = fig.add_subplot(111, projection='3d')

# 绘制球体 (用散点图表示)
colors = df[['r', 'g', 'b']].values
ax.scatter(df['x'], df['y'], df['z'], 
           c=colors, 
           s=df['radius']*1000,  # 调整大小以便可视化
           alpha=0.6)

# 设置坐标轴范围
ax.set_xlim(0, 10)
ax.set_ylim(0, 10)
ax.set_zlim(0, 10)

ax.set_xlabel('X')
ax.set_ylabel('Y')
ax.set_zlabel('Z')
ax.set_title('Ball Collision Simulation - Frame 0')

plt.savefig('visualization.png', dpi=150)
plt.show()
```

### 生成动画

使用 Python 生成动画：

```python
import pandas as pd
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D
import matplotlib.animation as animation
import glob
import re

# 获取所有帧文件并排序
frame_files = sorted(glob.glob('output/frame_*.csv'))

fig = plt.figure(figsize=(10, 10))
ax = fig.add_subplot(111, projection='3d')

def update_frame(frame_file):
    ax.clear()
    df = pd.read_csv(frame_file)
    colors = df[['r', 'g', 'b']].values
    ax.scatter(df['x'], df['y'], df['z'], 
               c=colors, 
               s=df['radius']*1000,
               alpha=0.6)
    
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 10)
    ax.set_zlim(0, 10)
    ax.set_xlabel('X')
    ax.set_ylabel('Y')
    ax.set_zlabel('Z')
    
    # 从文件名提取帧号
    frame_num = re.search(r'frame_(\d+)', frame_file).group(1)
    ax.set_title(f'Ball Collision - Frame {frame_num}')

# 创建动画
ani = animation.FuncAnimation(fig, update_frame, 
                              frames=frame_files, 
                              interval=100,
                              repeat=True)

# 保存为GIF或MP4
ani.save('collision_animation.gif', writer='pillow', fps=10)
# 或保存为MP4: ani.save('collision_animation.mp4', writer='ffmpeg', fps=10)

plt.show()
```

## 性能优化

### 调整球体数量

在 `src/glcuda.cu` 中修改：

```cpp
const int SPHERE_NUMBER = 64*4; // 默认256个球体
```

### 调整 GPU 计算配置

根据您的 GPU 性能，可以调整 CUDA kernel 配置：

```cpp
dim3 blockSize(SPHERE_NUMBER);  // 每个block的线程数
dim3 gridSize(1);                // block数量
```

### 调整空间大小

```cpp
const int SPACESIZE = 10; // 空间大小 (10x10x10)
```

## 故障排除

### 编译错误

**问题**: `nvcc: command not found`

**解决**: 确保 CUDA 已安装并添加到 PATH：

```bash
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
```

建议将上述命令添加到 `~/.bashrc` 或 `~/.bash_profile` 中。

**问题**: `unsupported GPU architecture 'compute_60'`

**解决**: 修改 Makefile 中的 `-arch=sm_XX` 参数以匹配您的 GPU 架构。

### 运行错误

**问题**: `CUDA Error: no CUDA-capable device is detected`

**解决**: 
1. 检查 GPU 驱动是否正确安装：`nvidia-smi`
2. 确认 CUDA 版本与驱动兼容

**问题**: `CUDA Error: out of memory`

**解决**: 减少球体数量或增加 GPU 显存。

### 性能问题

**问题**: 模拟运行很慢

**解决**: 
1. 检查是否使用了正确的 GPU 架构编译选项
2. 确认程序在 GPU 上运行而非 CPU
3. 调整球体数量和空间大小

## 清理

清理编译产物和输出文件：

```bash
make clean
```

## 与原 Windows 版本的差异

| 特性 | Windows 版本 | Linux 版本 |
|------|-------------|-----------|
| 图形界面 | GLUT/OpenGL 实时渲染 | 无图形界面，数据输出 |
| 构建系统 | Visual Studio 项目 | Makefile |
| 输出方式 | 窗口显示 | CSV 文件 |
| 运行方式 | 交互式 | 命令行批处理 |
| 物理计算 | CUDA kernel | **完全相同** |

## 技术支持

如有问题，请在项目 GitHub 页面提交 issue：
https://github.com/XWH19m10129/Ball-Collision-Cuda-Accelerating/issues

## 许可证

本项目采用与原项目相同的许可证。详见 LICENSE 文件。
