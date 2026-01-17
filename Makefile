# Makefile for Ball Collision CUDA Project (Linux)

# CUDA编译器
NVCC = nvcc

# CUDA路径 (自动检测，可以手动覆盖)
CUDA_PATH ?= /usr/local/cuda

# 编译选项
# -arch=sm_60: 适用于大多数现代NVIDIA GPU (可根据实际GPU调整)
# -O2: 优化级别
# -Xcompiler -Wall: 传递给C++编译器的警告选项
NVCC_FLAGS = -O2 -arch=sm_60 -Xcompiler -Wall

# 源文件
SRC = src/glcuda.cu

# 目标文件
TARGET = bin/ball_collision

# 链接库
LIBS = -lm

# 默认目标
all: $(TARGET)

# 创建bin目录并编译
$(TARGET): $(SRC)
	@mkdir -p bin
	$(NVCC) $(NVCC_FLAGS) -o $(TARGET) $(SRC) $(LIBS)
	@echo "编译完成: $(TARGET)"

# 清理编译产物
clean:
	rm -f $(TARGET)
	rm -rf output/*.csv
	@echo "清理完成"

# 运行程序 (默认1000帧)
run: $(TARGET)
	@mkdir -p output
	./$(TARGET)

# 运行程序 (自定义帧数)
# 使用方法: make run-frames FRAMES=500
run-frames: $(TARGET)
	@mkdir -p output
	./$(TARGET) $(FRAMES)

# 显示帮助信息
help:
	@echo "可用的make目标:"
	@echo "  make          - 编译项目"
	@echo "  make clean    - 清理编译产物和输出文件"
	@echo "  make run      - 编译并运行 (默认1000帧)"
	@echo "  make run-frames FRAMES=N - 编译并运行N帧"
	@echo "  make help     - 显示此帮助信息"

.PHONY: all clean run run-frames help
