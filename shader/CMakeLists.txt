if(NOT Slang_SLANGC_EXECUTABLE OR NOT EXISTS "${Slang_SLANGC_EXECUTABLE}")
    message(FATAL_ERROR "slangc not found. Set Slang_SLANGC_EXECUTABLE or Slang_ROOT.")
endif()

# Top-level module files only — sub-directory files use 'implementing' and cannot be compiled standalone
file(GLOB SHADER_MODULE_FILES "${CMAKE_CURRENT_LIST_DIR}/*.slang")

# All shader files (for IDE source groups)
file(GLOB_RECURSE SHADER_ALL_FILES "${CMAKE_CURRENT_LIST_DIR}/*.slang")
set(SHADER_SUB_FILES ${SHADER_ALL_FILES})
list(REMOVE_ITEM SHADER_SUB_FILES ${SHADER_MODULE_FILES})

set(SHADER_OUTPUT_DIR "${CMAKE_CURRENT_LIST_DIR}/_autogen")
file(MAKE_DIRECTORY "${SHADER_OUTPUT_DIR}")

set(GENERATED_SHADER_HEADERS "")

message(STATUS "Slang shaders to compile:")
foreach(_f ${SHADER_MODULE_FILES})
    get_filename_component(_n "${_f}" NAME)
    message(STATUS "  ${_n}")
endforeach()

foreach(SHADER_FILE ${SHADER_MODULE_FILES})
    get_filename_component(SHADER_NAME "${SHADER_FILE}" NAME)        # e.g. math.slang
    string(REPLACE "." "_" EMBED_NAME "${SHADER_NAME}")              # e.g. math_slang

    set(OUTPUT_H   "${SHADER_OUTPUT_DIR}/${SHADER_NAME}.h")
    set(OUTPUT_DEP "${SHADER_OUTPUT_DIR}/${SHADER_NAME}.dep")

    add_custom_command(
        OUTPUT  "${OUTPUT_H}"
        COMMAND "${Slang_SLANGC_EXECUTABLE}"
                -depfile "${OUTPUT_DEP}"
                -source-embed-name  "${EMBED_NAME}"
                -source-embed-style text
                -emit-spirv-directly
                -matrix-layout-row-major
                -force-glsl-scalar-layout
                -fvk-use-entrypoint-name
                -lang   slang
                -profile spirv_1_6
                -target  spirv
                -g1 -O0
                "-I${CMAKE_CURRENT_LIST_DIR}"
                -o "${OUTPUT_H}"
                "${SHADER_FILE}"
        MAIN_DEPENDENCY "${SHADER_FILE}"
        DEPFILE         "${OUTPUT_DEP}"
        COMMENT "Compiling Slang shader: ${SHADER_NAME}"
        VERBATIM
    )

    list(APPEND GENERATED_SHADER_HEADERS "${OUTPUT_H}")
endforeach()

add_library(peacock_shaders INTERFACE)
target_sources(peacock_shaders INTERFACE ${GENERATED_SHADER_HEADERS})
target_include_directories(peacock_shaders INTERFACE "${SHADER_OUTPUT_DIR}")

source_group("Shaders"             FILES ${SHADER_MODULE_FILES})
source_group("Shaders/Sub-Modules" FILES ${SHADER_SUB_FILES})
source_group("Shaders/Generated"   FILES ${GENERATED_SHADER_HEADERS})
