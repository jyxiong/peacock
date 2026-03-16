#pragma once

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
  glm::vec3 cameraPosition; // Camera position in world space
  int useSky;               // Whether to use the sky rendering
};

struct VolumeDesc {
  glm::mat4 worldToIndex;  // grid->worldToIndexF() 的 4x4 矩阵
  glm::vec3 bboxMin;       // index-space AABB min（来自 grid->indexBBox().min()）
  float     densityScale;
  glm::vec3 bboxMax;       // index-space AABB max
  float     stepSize;      // 步进大小（index space voxel 单位）
};

NAMESPACE_SHADERIO_END()