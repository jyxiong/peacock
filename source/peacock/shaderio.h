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
};

struct SceneInfo {
  glm::mat4 viewProjMatrix; // View projection matrix for the scene
  glm::mat4 projInvMatrix;  // Inverse projection matrix for the scene
  glm::mat4 viewInvMatrix;  // Inverse view matrix for the scene
  glm::vec4 cameraPositionUseSky;      // xyz: camera position, w: useSky
  glm::vec4 cameraForwardTanHalfFov;   // xyz: forward, w: tan(fov/2)
  glm::vec4 cameraRightAspect;         // xyz: right, w: aspect
  glm::vec4 cameraUpPad;               // xyz: up, w: padding
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