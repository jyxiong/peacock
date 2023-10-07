#version 460 
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_ray_query : require

layout(local_size_x = 16, local_size_y = 8, local_size_z = 1) in;

layout(binding = 0, set = 0, scalar) buffer storageBuffer
{
  vec3 imageData[];
};

layout(binding = 1, set = 0) uniform accelerationStructureEXT tlas;

void main()
{
  const uvec2 resolution = uvec2(800, 600);

  const uvec2 pixel = gl_GlobalInvocationID.xy;

  if (pixel.x >= resolution.x || pixel.y >= resolution.y)
  {
    return;
  }

  const vec3 cameraPosition = vec3(-0.001, 1.0, 6.0);
  vec3 rayOrigin = cameraPosition;

  const vec2 screenUV = 2.0 * vec2(pixel + 0.5) / vec2(resolution) - 1.0;

  const float fovVerticalSlope = 1.0 / 5.0;
  vec3 rayDirection = vec3(fovVerticalSlope * screenUV, -1.0);

  rayQueryEXT rayQuery;
  rayQueryInitializeEXT(rayQuery, tlas, gl_RayFlagsNoneEXT, 0xFF, rayOrigin, 0.0, rayDirection, 10000.0);

  while (rayQueryProceedEXT(rayQuery))
  {
  }

  const float t = rayQueryGetIntersectionTEXT(rayQuery, true);

  uint index = resolution.x * pixel.y + pixel.x;

  imageData[index] = vec3(t / 10.0);
}