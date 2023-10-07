#version 460 
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_ray_query : require

layout(local_size_x = 16, local_size_y = 8, local_size_z = 1) in;

layout(binding = 0, set = 0, scalar) buffer storageBuffer
{
  vec3 imageData[];
};

layout(binding = 1, set = 0) uniform accelerationStructureEXT tlas;

layout(binding = 2, set = 0, scalar) buffer Vertices
{
  vec3 vertices[];
};

layout(binding = 3, set = 0, scalar) buffer Indices
{
  uint indices[];
};

float stepAndOutputRNGFloat(inout uint rngState)
{
  // Condensed version of pcg_output_rxs_m_xs_32_32, with simple conversion to floating-point [0,1].
  rngState  = rngState * 747796405 + 1;
  uint word = ((rngState >> ((rngState >> 28) + 4)) ^ rngState) * 277803737;
  word      = (word >> 22) ^ word;
  return float(word) / 4294967295.0f;
}

vec3 skyColor(vec3 direction)
{
  if(direction.y > 0.0f)
  {
    return mix(vec3(1.0f), vec3(0.25f, 0.5f, 1.0f), direction.y);
  }
  else
  {
    return vec3(0.03f);
  }
}

struct HitInfo
{
  vec3 color;
  vec3 worldPosition;
  vec3 worldNormal;
};

HitInfo getObjectHitInfo(rayQueryEXT rayQuery)
{
  HitInfo result;

  // Get the ID of the triangle
  const int primitiveID = rayQueryGetIntersectionPrimitiveIndexEXT(rayQuery, true);

  // Get the indices of the vertices of the triangle
  const uint i0 = indices[3 * primitiveID + 0];
  const uint i1 = indices[3 * primitiveID + 1];
  const uint i2 = indices[3 * primitiveID + 2];

  // Get the vertices of the triangle
  const vec3 v0 = vertices[i0];
  const vec3 v1 = vertices[i1];
  const vec3 v2 = vertices[i2];

  // barycentric coordinates of the intersection
  vec3 barycentrics = vec3(0.0, rayQueryGetIntersectionBarycentricsEXT(rayQuery, true));
  barycentrics.x = 1.0 - barycentrics.y - barycentrics.z;

  // Compute the world position of the intersection
  result.worldPosition = barycentrics.x * v0 + barycentrics.y * v1 + barycentrics.z * v2;
  
  // Compute the normal of the triangle in object space
  result.worldNormal = normalize(cross(v1 - v0, v2 - v0));

  result.color = vec3(0.7);

  return result;
}

void main()
{
  const uvec2 resolution = uvec2(800, 600);

  const uvec2 pixel = gl_GlobalInvocationID.xy;

  if (pixel.x >= resolution.x || pixel.y >= resolution.y)
  {
    return;
  }

  const vec3 cameraPosition = vec3(-0.001, 1.0, 6.0);
  const float fovVerticalSlope = 1.0 / 5.0;
  const float aspectRatio = float(resolution.x) / float(resolution.y);

  vec3 rayOrigin = cameraPosition;

  const vec2 screenUV = (2.0 * vec2(pixel + 0.5) / vec2(resolution) - 1.0);
  vec3 rayDirection = vec3(fovVerticalSlope * screenUV * vec2(aspectRatio, 1), -1.0);

  vec3 accumulatedRayColor = vec3(1.0);
  vec3 pixelColor          = vec3(0.0);

  // trace the ray
  for (int tracedSegments = 0; tracedSegments < 32; tracedSegments++)
  {
    rayQueryEXT rayQuery;
    rayQueryInitializeEXT(rayQuery, tlas, gl_RayFlagsNoneEXT, 0xFF, rayOrigin, 0.0, rayDirection, 10000.0);

    // get closet hit
    while (rayQueryProceedEXT(rayQuery))
    {
    }

    // check if the ray hit something
    if(rayQueryGetIntersectionTypeEXT(rayQuery, true) == gl_RayQueryCommittedIntersectionTriangleEXT)
    {
      HitInfo hitInfo = getObjectHitInfo(rayQuery);

      hitInfo.worldNormal = faceforward(hitInfo.worldNormal, rayDirection, hitInfo.worldNormal);

      accumulatedRayColor *= hitInfo.color;

      rayOrigin = hitInfo.worldPosition + 0.0001 * hitInfo.worldNormal;
      rayDirection = reflect(rayDirection, hitInfo.worldNormal);
    }
    else
    {
      // Ray hit the sky
      pixelColor = accumulatedRayColor * skyColor(rayDirection);
      break;
    }

  }

  uint index = resolution.x * pixel.y + pixel.x;
  imageData[index] = pixelColor;
}