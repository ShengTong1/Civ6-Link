# civtrace 构建 —— MinGW-w64（MSYS2 MINGW64 或 choco mingw 均可）
# 依赖：MinHook 源码（BSD-2），锁定 v1.3.4。在 CivLink-M0A-audit 根目录执行：
#   git clone --depth 1 --branch v1.3.4 https://github.com/TsudaKageyu/minhook.git deps/MinHook
#
# 常规：  mingw32-make              （或 mingw32-make CXX=g++）
# 清理：  mingw32-make clean

CXX      ?= x86_64-w64-mingw32-g++
CXXFLAGS := -std=c++17 -O2 -Wall -Wextra -Wno-unused-parameter \
            -D_WIN32_WINNT=0x0601 -D__USE_MINGW_ANSI_STDIO=1 -D_CRT_SECURE_NO_WARNINGS \
            -I../deps/MinHook/include

MINHOOK_SRCS := ../deps/MinHook/src/buffer.c \
                ../deps/MinHook/src/hook.c \
                ../deps/MinHook/src/trampoline.c \
                ../deps/MinHook/src/HDE/hde32.c \
                ../deps/MinHook/src/HDE/hde64.c

all: civtrace.dll civinject.exe

civtrace.dll: trace_dll.cpp $(MINHOOK_SRCS)
	$(CXX) $(CXXFLAGS) -shared -static $^ -o $@ -lws2_32 -lpsapi

civinject.exe: injector.cpp
	$(CXX) -std=c++17 -O2 -Wall -static injector.cpp -o $@ -ladvapi32

clean:
	rm -f civtrace.dll civinject.exe

.PHONY: all clean
