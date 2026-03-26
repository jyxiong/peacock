#pragma once

#include <cstddef>
#include <type_traits>

#include <nvshaders/slang_types.h>

NAMESPACE_SHADERIO_BEGIN()

enum BindingIndex {
  eOutImage = 0,
  eSceneDesc = 1,
  eVolumeGrid = 2,  // StructuredBuffer<uint> — raw NanoVDB bytes
  eVolumeDesc = 3,  // VolumeDesc UBO
  eHdrImage = 4,
};

struct SceneInfo {
  glm::mat4 viewProjMatrix; // View projection matrix for the scene
  glm::mat4 projInvMatrix;  // Inverse projection matrix for the scene
  glm::mat4 viewInvMatrix;  // Inverse view matrix for the scene
  glm::vec3 cameraPosition; // w is unused, padding for layout match with shader
  int useSky{0};            // Whether to use sky color when ray misses the volume
  unsigned int sampleCount{4};       // Number of samples per pixel
  unsigned int frameIndex{0};        // Current frame index (for RNG seed)
  int maxScatterDepth{8};            // Maximum number of scattering events per path
  int pad{0};
};

struct VolumeDesc {
  glm::mat4 worldToIndex{1.0f};
  glm::vec4 bboxMinDensityScale{0.0f, 0.0f, 0.0f, 0.1f};
  glm::vec4 bboxMaxStepSize{0.0f, 0.0f, 0.0f, 0.5f};
  glm::uvec4 nanoGridInfo{0u, 0u, 0u, 0u};
};

static_assert(std::is_standard_layout_v<SceneInfo>);
static_assert(std::is_standard_layout_v<VolumeDesc>);
static_assert(offsetof(VolumeDesc, bboxMinDensityScale) == sizeof(glm::mat4));
static_assert(offsetof(VolumeDesc, bboxMaxStepSize) == sizeof(glm::mat4) + sizeof(glm::vec4));
static_assert(offsetof(VolumeDesc, nanoGridInfo) == sizeof(glm::mat4) + sizeof(glm::vec4) * 2);

NAMESPACE_SHADERIO_END()