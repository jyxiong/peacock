#pragma once

enum BindingIndex
{
  eOutImage = 0,
  eSceneDesc = 1,
};

struct SceneInfo {
  float4x4 viewProjMatrix; // View projection matrix for the scene
  float4x4 projInvMatrix;  // Inverse projection matrix for the scene
  float4x4 viewInvMatrix;  // Inverse view matrix for the scene
  float3 cameraPosition;   // Camera position in world space
  int useSky;              // Whether to use the sky rendering
};
