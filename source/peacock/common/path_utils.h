  #pragma once

#include <filesystem>
#include <vector>

#include <nvutils/file_operations.hpp>

namespace peacock {

inline static std::vector<std::filesystem::path> getResourcesDirs()
{
  std::filesystem::path exePath = nvutils::getExecutablePath().parent_path();
  return {
      std::filesystem::absolute(exePath / TARGET_EXE_TO_ROOT_DIRECTORY / "resources"),
      std::filesystem::absolute(exePath / "resources")  //
  };
}

inline static std::vector<std::filesystem::path> getShaderDirs()
{
  std::filesystem::path exePath = nvutils::getExecutablePath().parent_path();
  return {
      std::filesystem::absolute(exePath / TARGET_EXE_TO_SOURCE_DIRECTORY / "shaders"),
      std::filesystem::absolute(exePath / TARGET_EXE_TO_NVSHADERS_DIRECTORY),
      std::filesystem::absolute(exePath / TARGET_EXE_TO_ROOT_DIRECTORY),
      std::filesystem::absolute(exePath / TARGET_EXE_TO_ROOT_DIRECTORY / "common" / "shaders"),
      std::filesystem::absolute(NVSHADERS_DIR),
      std::filesystem::absolute(exePath / TARGET_NAME "_files" / "shaders"),
      std::filesystem::absolute(exePath / "common"),
      std::filesystem::absolute(exePath / "common" / "shaders"),
      std::filesystem::absolute(exePath),
  };
}

}  // namespace peacock