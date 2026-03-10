cmake_minimum_required(VERSION 3.22...3.31)
project(peacock LANGUAGES C CXX)

option(NVPRO2_ENABLE_nvgl off)
option(USE_DEFAULT_SCENE "Using a default scene at startup" ON)

# Disable unused libraries from nvpro_core2 - we use local copy
set(NVPRO2_ENABLE_nvvkgltf OFF CACHE BOOL "Disable nvvkgltf from nvpro_core2" FORCE)
set(NVPRO2_ENABLE_nvvkglsl OFF CACHE BOOL "Disable nvvkglsl from nvpro_core2" FORCE)

# Set Slang version
# set(Slang_VERSION 2026.1)

# Add the cmake folder to the module path
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
find_package(NvproCore2 REQUIRED)

# Get the name of the current directory
get_filename_component(PROJECT_NAME ${CMAKE_CURRENT_SOURCE_DIR} NAME)
project(${PROJECT_NAME} VERSION 2.0 LANGUAGES C CXX)
message(STATUS "Processing: ${PROJECT_NAME}")

add_subdirectory(source)