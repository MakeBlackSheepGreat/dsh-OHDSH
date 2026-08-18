cmake_minimum_required(VERSION 3.5.0)
project(dsh_host)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH}/include/node)

add_library(dsh_host SHARED dsh_host.cpp)

# 输出到 hvigor 指定的库输出目录（obj/arm64-v8a），否则产物留在 .cxx 构建树
set_target_properties(dsh_host PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}
  LIBRARY_OUTPUT_DIRECTORY_RELEASE ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}
  LIBRARY_OUTPUT_DIRECTORY_DEBUG ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}
)

# 注：dsh_host.cpp 不使用日志 API；SDK 26 native sysroot 无 liblog.so（仅 libhilog_ndk.z.so），
# 若后续需要日志请链接 hilog_ndk 并 include <hilog/log.h>。
# target_link_libraries(dsh_host PUBLIC hilog_ndk)
