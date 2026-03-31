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
  unsigned int sampleCount{1};       // Number of samples per pixel
  unsigned int frameIndex{0};        // Current frame index (for RNG seed)
  int maxScatterDepth{3};            // Maximum number of scattering events per path
  int pad{0};
};

struct VolumeDesc {
  // ── Coordinate transform ──────────────────────────────────────────────────
  glm::mat4 worldToIndex{1.0f};              // world → index-space transform

  // ── Bounding box (world space) ────────────────────────────────────────────
  glm::vec3 bboxMin{0.0f};  float _pad0{0.0f};
  glm::vec3 bboxMax{0.0f};  float stepSize{0.5f};  // ray-march step hint

  // ── Medium optical properties (scale factors applied to density) ──────────
  glm::vec3 sigma_a{0.0f};       float majorant{1.0f};       // absorption scale + global extinction bound
  glm::vec3 sigma_s{1.0f};       float densityScale{0.1f};   // scattering scale + raw→extinction factor
  glm::vec3 Le{0.0f};            float g{0.0f};              // emission scale + HG asymmetry
};

static_assert(std::is_standard_layout_v<SceneInfo>);
static_assert(std::is_standard_layout_v<VolumeDesc>);
static_assert(offsetof(VolumeDesc, bboxMin)  == 64);
static_assert(offsetof(VolumeDesc, bboxMax)  == 80);
static_assert(offsetof(VolumeDesc, sigma_a)  == 96);
static_assert(offsetof(VolumeDesc, sigma_s)  == 112);
static_assert(offsetof(VolumeDesc, Le)       == 128);
static_assert(sizeof(VolumeDesc) == 144);

NAMESPACE_SHADERIO_END()