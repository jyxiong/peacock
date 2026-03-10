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
    nvpro2::nvapp
    nvpro2::nvgui
    nvpro2::nvslang
    nvpro2::nvutils
    nvpro2::nvvk
)

add_project_definitions(${PROJECT_NAME})


#------------------------------------------------------------------------------------------------------------------------------
# Compile shaders
file(GLOB SHADER_SLANG_FILES "peacock/shaders/*.slang")
file(GLOB SHADER_GLSL_FILES "peacock/shaders/*.glsl")
file(GLOB SHADER_H_FILES "peacock/shaders/*.h")

set(SHADER_OUTPUT_DIR "${CMAKE_CURRENT_LIST_DIR}/peacock/_autogen")

compile_slang(
    "${SHADER_SLANG_FILES}"
     "${SHADER_OUTPUT_DIR}"
    GENERATED_SHADER_SLANG_HEADERS
    EXTRA_FLAGS "-I${NVSHADERS_DIR}"
)

# Add shader files to the project
source_group("Shaders" FILES ${SHADER_SLANG_FILES} ${SHADER_GLSL_FILES} ${SHADER_H_FILES})
source_group("Shaders/Compiled" FILES ${GENERATED_SHADER_SLANG_HEADERS} ${GENERATED_SHADER_GLSL_HEADERS})

# Add the output shader headers (target) directly to the executable
# This allows to compile the shaders when the executable is built
target_sources(${PROJECT_NAME} PRIVATE ${GENERATED_SHADER_SLANG_HEADERS} ${GENERATED_SHADER_GLSL_HEADERS} ${SHADER_H_FILES})

#------------------------------------------------------------------------------------------------------------------------------
# Installation, copy files

copy_to_runtime_and_install(${PROJECT_NAME}
    LOCAL_DIRS "${CMAKE_CURRENT_LIST_DIR}/peacock/shaders"
    AUTO
)