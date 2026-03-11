#pragma once

#include <glm/glm.hpp>

namespace shaderio {

enum BindingIndex {
  eOutImage = 0,
  eSceneDesc = 1,
};

struct SceneInfo {
  glm::mat4 viewProjMatrix; // View projection matrix for the scene
  glm::mat4 projInvMatrix;  // Inverse projection matrix for the scene
  glm::mat4 viewInvMatrix;  // Inverse view matrix for the scene
  glm::vec3 cameraPosition; // Camera position in world space
  int useSky;               // Whether to use the sky rendering
};

} // namespace shaderio