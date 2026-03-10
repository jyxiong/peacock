#pragma once

#include "common/io_gltf.h"

NAMESPACE_SHADERIO_BEGIN()

// Binding Points
enum BindingPoints
{
  eTextures = 0,  // Binding point for textures
  eOutImage,      // Binding point for output image
  eTlas,          // Top-level acceleration structure
};

NAMESPACE_SHADERIO_END()
