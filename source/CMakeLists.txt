file(GLOB_RECURSE SOURCES
    "*.cpp"
)

add_executable(${PROJECT_NAME}
    ${SOURCES}
)

target_include_directories(${PROJECT_NAME} 
PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_link_libraries(${PROJECT_NAME}
PUBLIC
    openvdb
    nanovdb
    stb
    nvpro2::nvapp
    nvpro2::nvgui
    nvpro2::nvslang
    nvpro2::nvutils
    nvpro2::nvvk
)

add_project_definitions(${PROJECT_NAME})


#------------------------------------------------------------------------------------------------------------------------------
# Compile shaders
file(GLOB_RECURSE SHADER_SLANG_FILES "${CMAKE_CURRENT_LIST_DIR}/peacock/shader/*.slang")

# Modules cant be compiled directly
list(FILTER SHADER_SLANG_FILES EXCLUDE REGEX ".*/module/.*")

set(SHADER_OUTPUT_DIR "${CMAKE_CURRENT_LIST_DIR}/peacock/_autogen")

compile_slang(
    "${SHADER_SLANG_FILES}"
     "${SHADER_OUTPUT_DIR}"
    HEADERS_VAR GENERATED_SHADER_SLANG_HEADERS
    EXTRA_FLAGS 
        "-I${NVSHADERS_DIR}"
        "-I${CMAKE_CURRENT_LIST_DIR}/../external/openvdb/nanovdb"
)

# Add shader files to the project
source_group("Shaders" FILES ${SHADER_SLANG_FILES})
source_group("Shaders/Compiled" FILES ${GENERATED_SHADER_SLANG_HEADERS})

# Add the output shader headers (target) directly to the executable
# This allows to compile the shaders when the executable is built
target_sources(${PROJECT_NAME} PRIVATE ${GENERATED_SHADER_SLANG_HEADERS})

#------------------------------------------------------------------------------------------------------------------------------
# Installation, copy files

copy_to_runtime_and_install(${PROJECT_NAME}
    LOCAL_DIRS "${CMAKE_CURRENT_LIST_DIR}/peacock/shader"
    AUTO
)