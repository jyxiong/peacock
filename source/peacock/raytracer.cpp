#include "vulkan/vulkan_core.h"
#define VMA_DYNAMIC_VULKAN_FUNCTIONS                                           \
  1 // Use dynamic Vulkan functions for VMA (Vulkan Memory Allocator)
#define VMA_IMPLEMENTATION // Implementation of the Vulkan Memory Allocator
#define VMA_LEAK_LOG_FORMAT(format, ...)                                       \
  {                                                                            \
    printf((format), __VA_ARGS__);                                             \
    printf("\n");                                                              \
  }

#define STB_IMAGE_IMPLEMENTATION


#include "peacock/raytracer.h"

#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <stdexcept>

#include <openvdb/openvdb.h>
#include <nanovdb/NanoVDB.h>
#include <nanovdb/tools/CreateNanoGrid.h>
#include <stb/stb_image.h>

#include <nvvk/check_error.hpp>
#include <nvvk/debug_util.hpp>
#include <nvvk/formats.hpp>
#include <nvgui/camera.hpp>

#include "peacock/_autogen/raytrace.slang.h"
#include "peacock/common/path_utils.h"

using namespace peacock;

namespace {

void setupCameraForBox(const std::shared_ptr<nvutils::CameraManipulator>& camera,
                       const glm::vec3& boxMin,
                       const glm::vec3& boxMax,
                       float aspect) {
  const glm::vec3 center = (boxMin + boxMax) * 0.5f;
  const glm::vec3 halfExtent = (boxMax - boxMin) * 0.5f;

  const float safeAspect = std::max(aspect, 0.1f);
  const float tanHalfFovY = std::tan(0.5f * glm::radians(camera->getFov()));
  const float tanHalfFovX = tanHalfFovY * safeAspect;

  const float distX = halfExtent.x / std::max(tanHalfFovX, 1e-4f);
  const float distY = halfExtent.y / std::max(tanHalfFovY, 1e-4f);
  const float margin = 1.15f;
  const float distance = std::max(distX, distY) * margin + halfExtent.z;

  const glm::vec3 eye = center + glm::vec3(0.0f, 0.0f, distance);
  camera->setLookat(eye, center, glm::vec3(0.0f, 1.0f, 0.0f));
}

glm::mat4 makeWorldToIndexMatrix(const nanovdb::Map& map) {
  const float tx = -(map.mVecF[0] * map.mInvMatF[0] + map.mVecF[1] * map.mInvMatF[3] +
                     map.mVecF[2] * map.mInvMatF[6]);
  const float ty = -(map.mVecF[0] * map.mInvMatF[1] + map.mVecF[1] * map.mInvMatF[4] +
                     map.mVecF[2] * map.mInvMatF[7]);
  const float tz = -(map.mVecF[0] * map.mInvMatF[2] + map.mVecF[1] * map.mInvMatF[5] +
                     map.mVecF[2] * map.mInvMatF[8]);

  return glm::mat4(
      map.mInvMatF[0], map.mInvMatF[3], map.mInvMatF[6], 0.0f,
      map.mInvMatF[1], map.mInvMatF[4], map.mInvMatF[7], 0.0f,
      map.mInvMatF[2], map.mInvMatF[5], map.mInvMatF[8], 0.0f,
      tx, ty, tz, 1.0f);
}

openvdb::FloatGrid::Ptr loadFirstFloatGrid(const std::filesystem::path& vdbPath) {
  openvdb::initialize();

  openvdb::io::File file(vdbPath.string());
  file.open();

  openvdb::FloatGrid::Ptr floatGrid;
  for (auto it = file.beginName(); it != file.endName(); ++it) {
    auto gridBase = file.readGrid(*it);
    floatGrid = openvdb::gridPtrCast<openvdb::FloatGrid>(gridBase);
    if (floatGrid) {
      break;
    }
  }

  file.close();

  if (!floatGrid) {
    throw std::runtime_error("No float grid found in VDB file: " + vdbPath.string());
  }

  return floatGrid;
}

shaderio::VolumeDesc makeVolumeDesc(const nanovdb::NanoGrid<float>& grid,
                                    uint32_t gridByteSize) {
  shaderio::VolumeDesc desc{};
  desc.worldToIndex = glm::transpose(makeWorldToIndexMatrix(grid.map()));

  const auto bbox = grid.worldBBox();
  printf("[Volume] worldBBox min=(%.4f, %.4f, %.4f) max=(%.4f, %.4f, %.4f)\n",
         bbox.min()[0], bbox.min()[1], bbox.min()[2],
         bbox.max()[0], bbox.max()[1], bbox.max()[2]);
  desc.bboxMinDensityScale =
      glm::vec4(static_cast<float>(bbox.min()[0]),
                static_cast<float>(bbox.min()[1]),
                static_cast<float>(bbox.min()[2]), 0.1f);
  desc.bboxMaxStepSize = glm::vec4(static_cast<float>(bbox.max()[0]),
                                   static_cast<float>(bbox.max()[1]),
                                   static_cast<float>(bbox.max()[2]), 0.5f);
  // Majorant: max density value × densityScale, stored as float bits for the shader
  const float maxDensity = static_cast<float>(grid.tree().root().maximum());
  const float sigmaMax   = std::max(maxDensity * 0.1f, 1e-6f);  // 0.1f == densityScale default
  desc.nanoGridInfo = glm::uvec4(gridByteSize, (gridByteSize + 3u) / 4u,
                                 std::bit_cast<uint32_t>(sigmaMax), 0u);
  return desc;
}

} // namespace

void Raytracer::onAttach(nvapp::Application *app) {
  m_app = app;

  // Query ray tracing properties used by pipeline/SBT creation.
  VkPhysicalDeviceProperties2 props2{
      VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2};
  props2.pNext = &m_rtProperties;
  vkGetPhysicalDeviceProperties2(m_app->getPhysicalDevice(), &props2);

  // Initialize the VMA allocator
  VmaAllocatorCreateInfo allocatorInfo = {
      .flags = VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
      .physicalDevice = app->getPhysicalDevice(),
      .device = app->getDevice(),
      .instance = app->getInstance(),
      .vulkanApiVersion = VK_API_VERSION_1_4,
  };
  m_allocator.init(allocatorInfo);

  // The VMA allocator is used for all allocations, the staging uploader will
  // use it for staging buffers and images
  m_stagingUploader.init(&m_allocator, true);

  // Setting up the Slang compiler for hot reload shader
  m_slangCompiler.addSearchPaths(peacock::getShaderDirs());
  m_slangCompiler.defaultTarget();
  m_slangCompiler.defaultOptions();
  m_slangCompiler.addOption(
      {slang::CompilerOptionName::DebugInformation,
       {slang::CompilerOptionValueKind::Int, SLANG_DEBUG_INFO_LEVEL_MAXIMAL}});

  // Acquiring the texture sampler which will be used for displaying the GBuffer
  m_samplerPool.init(app->getDevice());
  NVVK_CHECK(m_samplerPool.acquireSampler(m_linearSampler));
  NVVK_DBG_NAME(m_linearSampler);

  // Create the G-Buffers
  nvvk::GBufferInitInfo gBufferInit{
      .allocator = &m_allocator,
      .colorFormats = {VK_FORMAT_R16G16B16A16_SFLOAT},  // float16 for HDR progressive accumulation
      .depthFormat = nvvk::findDepthFormat(m_app->getPhysicalDevice()),
      .imageSampler = m_linearSampler,
      .descriptorPool = m_app->getTextureDescriptorPool(),
  };
  m_gBuffers.init(gBufferInit);

  // Initialize SBT generator with queried ray tracing properties.
  m_sbtGenerator.init(m_app->getDevice(), m_rtProperties);

  loadVolume("/home/jyxiong/Projects/peacock/asset/bunny.vdb");
  loadHdrIbl("/home/jyxiong/Projects/peacock/asset/belfast_sunset_puresky_2k.hdr");

  setupCameraForBox(m_cameraManip, glm::vec3(m_volumeDesc.bboxMinDensityScale),
                    glm::vec3(m_volumeDesc.bboxMaxStepSize), 1.0f);

  createResources();
  createRaytraceDescriptorLayout();
  createRayTracingPipeline();
}

void Raytracer::onDetach() {
  NVVK_CHECK(vkQueueWaitIdle(m_app->getQueue(0).queue));

  vkDestroyPipelineLayout(m_app->getDevice(), m_rtPipelineLayout, nullptr);
  vkDestroyPipeline(m_app->getDevice(), m_rtPipeline, nullptr);

  m_allocator.destroyBuffer(m_sbtBuffer);
  m_allocator.destroyBuffer(m_bSceneInfo);
  m_allocator.destroyBuffer(m_bVolumeDesc);
  m_allocator.destroyBuffer(m_bVolumeGrid);

  if (m_hdrImageView != VK_NULL_HANDLE) {
    vkDestroyImageView(m_app->getDevice(), m_hdrImageView, nullptr);
    m_hdrImageView = VK_NULL_HANDLE;
  }
  m_allocator.destroyImage(m_hdrImage);

  m_rtDescPack.deinit();
  m_gBuffers.deinit();
  m_samplerPool.deinit();
  m_stagingUploader.deinit();
  m_sbtGenerator.deinit();
  m_allocator.deinit();
}

void Raytracer::onResize(VkCommandBuffer cmd, const VkExtent2D &size) {
  NVVK_CHECK(m_gBuffers.update(cmd, size));
  if (size.height > 0) {
    const float aspect = static_cast<float>(size.width) / static_cast<float>(size.height);
    setupCameraForBox(m_cameraManip, glm::vec3(m_volumeDesc.bboxMinDensityScale),
                      glm::vec3(m_volumeDesc.bboxMaxStepSize), aspect);
  }
}

void Raytracer::onUIRender() {
  if (ImGui::Begin("Viewport")) {
    ImGui::Image(ImTextureID(m_gBuffers.getDescriptorSet()),
                 ImGui::GetContentRegionAvail());
  }
  ImGui::End();

  if (ImGui::Begin("Settings")) {
    ImGui::TextDisabled("%d FPS / %.3fms",
                        static_cast<int>(ImGui::GetIO().Framerate),
                        1000.F / ImGui::GetIO().Framerate);

    if (ImGui::CollapsingHeader("Camera")) {
      nvgui::CameraWidget(m_cameraManip);
    }

    if (ImGui::CollapsingHeader("Path Tracer", ImGuiTreeNodeFlags_DefaultOpen)) {
      bool changed = false;

      // Samples per pixel
      int spp = static_cast<int>(m_sceneInfo.sampleCount);
      if (ImGui::SliderInt("Samples / pixel", &spp, 1, 64)) {
        m_sceneInfo.sampleCount = static_cast<unsigned int>(spp);
        changed = true;
      }

      // Density scale — scales raw voxel values; also updates sigmaMax
      float ds = m_volumeDesc.bboxMinDensityScale.w;
      if (ImGui::SliderFloat("Density scale", &ds, 0.001f, 2.0f, "%.4f")) {
        m_volumeDesc.bboxMinDensityScale.w = ds;
        const float sigmaMax = std::max(m_maxDensity * ds, 1e-6f);
        m_volumeDesc.nanoGridInfo.z = std::bit_cast<uint32_t>(sigmaMax);
        changed = true;
      }

      // HG anisotropy: negative = back-scattering, 0 = isotropic, positive = forward-scattering
      if (ImGui::SliderFloat("HG anisotropy (g)", &m_hgG, -0.99f, 0.99f, "%.3f")) {
        changed = true;
      }

      // Maximum scattering depth per path
      if (ImGui::SliderInt("Max scatter depth", &m_sceneInfo.maxScatterDepth, 1, 32)) {
        changed = true;
      }

      ImGui::LabelText("Frame index", "%u", m_sceneInfo.frameIndex);

      if (ImGui::Button("Reset accumulation")) {
        changed = true;
      }

      if (changed) {
        m_sceneInfo.frameIndex = 0;
      }
    }
  }
  ImGui::End();
}

void Raytracer::onUIMenu() {
  if (ImGui::BeginMenu("File")) {
    if (ImGui::MenuItem("Exit", "Ctrl+Q"))
      m_app->close();
    ImGui::EndMenu();
  }
  if (ImGui::IsKeyPressed(ImGuiKey_Q) && ImGui::IsKeyDown(ImGuiKey_LeftCtrl))
    m_app->close();
}

void Raytracer::loadVolume(const std::filesystem::path& vdbPath) {
  if (!std::filesystem::exists(vdbPath)) {
    throw std::runtime_error("Volume file does not exist: " + vdbPath.string());
  }

  auto floatGrid = loadFirstFloatGrid(vdbPath);
  m_gridHandle = nanovdb::tools::createNanoGrid(*floatGrid);

  const auto* nanoGrid = m_gridHandle.grid<float>();
  if (!nanoGrid) {
    throw std::runtime_error("Failed to convert VDB float grid to NanoVDB: " +
                             vdbPath.string());
  }

  m_maxDensity = static_cast<float>(nanoGrid->tree().root().maximum());
  m_volumeDesc = makeVolumeDesc(*nanoGrid,
                                static_cast<uint32_t>(m_gridHandle.gridSize()));

  const VkDeviceSize gridByteSize = static_cast<VkDeviceSize>(m_gridHandle.gridSize());
  if(m_gridHandle.data() == nullptr) {
    throw std::runtime_error("NanoVDB handle does not contain raw grid data: " +
                             vdbPath.string());
  }

  // Upload buffers
  assert(m_stagingUploader.isAppendedEmpty());
  VkCommandBuffer cmd = m_app->createTempCmdBuffer();
  {
    m_allocator.destroyBuffer(m_bVolumeDesc);
    m_allocator.destroyBuffer(m_bVolumeGrid);

    // Create a buffer (UBO) to store the volume description
    NVVK_CHECK(m_allocator.createBuffer(m_bVolumeDesc, sizeof(shaderio::VolumeDesc),
                                        VK_BUFFER_USAGE_2_UNIFORM_BUFFER_BIT |
                                            VK_BUFFER_USAGE_2_TRANSFER_DST_BIT,
                                        VMA_MEMORY_USAGE_AUTO));
    NVVK_CHECK(m_stagingUploader.appendBuffer(m_bVolumeDesc, 0, sizeof(m_volumeDesc),
                                              &m_volumeDesc));
    NVVK_DBG_NAME(m_bVolumeDesc.buffer);


    NVVK_CHECK(m_allocator.createBuffer(m_bVolumeGrid, gridByteSize,
                      VK_BUFFER_USAGE_2_STORAGE_BUFFER_BIT |
                        VK_BUFFER_USAGE_2_TRANSFER_DST_BIT,
                      VMA_MEMORY_USAGE_AUTO));
    NVVK_CHECK(m_stagingUploader.appendBuffer(m_bVolumeGrid, 0, gridByteSize,
                                              m_gridHandle.data()));
    NVVK_DBG_NAME(m_bVolumeGrid.buffer);
  }

  m_stagingUploader.cmdUploadAppended(cmd);
  m_app->submitAndWaitTempCmdBuffer(cmd);
  m_stagingUploader.releaseStaging();
  m_volumeUploaded = true;
}

void Raytracer::loadHdrIbl(const std::filesystem::path &hdrPath) {
  int width, height, channels;
  auto* data = stbi_loadf(hdrPath.string().c_str(), &width, &height, &channels, 4);
  if (!data) {
    throw std::runtime_error("Failed to load HDR image: " + hdrPath.string());
  }
  auto imageByteSize = static_cast<VkDeviceSize>(width) * static_cast<VkDeviceSize>(height) * 4 * sizeof(float);

  assert(m_stagingUploader.isAppendedEmpty());
  VkCommandBuffer cmd = m_app->createTempCmdBuffer();
  {
    if (m_hdrImageView != VK_NULL_HANDLE) {
      vkDestroyImageView(m_app->getDevice(), m_hdrImageView, nullptr);
      m_hdrImageView = VK_NULL_HANDLE;
    }
    m_allocator.destroyImage(m_hdrImage);

    NVVK_CHECK(m_allocator.createImage(m_hdrImage, VkImageCreateInfo{
                                              .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
                                              .imageType = VK_IMAGE_TYPE_2D,
                                              .format = VK_FORMAT_R32G32B32A32_SFLOAT,
                                              .extent = {static_cast<uint32_t>(width), static_cast<uint32_t>(height), 1},
                                              .mipLevels = 1,
                                              .arrayLayers = 1,
                                              .samples = VK_SAMPLE_COUNT_1_BIT,
                                              .tiling = VK_IMAGE_TILING_OPTIMAL,
                                              .usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT,
                                              .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
                                              .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
                                          },
                                          VmaAllocationCreateInfo{
                                              .usage = VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
                                          }));
    NVVK_CHECK(m_stagingUploader.appendImage(m_hdrImage, imageByteSize, data,
                                             VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL));
    NVVK_DBG_NAME(m_hdrImage.image);
  }

  m_stagingUploader.cmdUploadAppended(cmd);
  m_app->submitAndWaitTempCmdBuffer(cmd);
  m_stagingUploader.releaseStaging();

  // Create image view for shader sampling
  const VkImageViewCreateInfo viewInfo{
      .sType    = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
      .image    = m_hdrImage.image,
      .viewType = VK_IMAGE_VIEW_TYPE_2D,
      .format   = VK_FORMAT_R32G32B32A32_SFLOAT,
      .subresourceRange = {.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT,
                           .baseMipLevel   = 0,
                           .levelCount     = 1,
                           .baseArrayLayer = 0,
                           .layerCount     = 1},
  };
  NVVK_CHECK(vkCreateImageView(m_app->getDevice(), &viewInfo, nullptr, &m_hdrImageView));
  NVVK_DBG_NAME(m_hdrImageView);

  stbi_image_free(data);
}

void Raytracer::onRender(VkCommandBuffer cmd) {
  if (m_rtPipeline == VK_NULL_HANDLE) {
    return;
  }
  updateSceneBuffer(cmd);
  raytrace(cmd);
}

void Raytracer::createResources() {
  SCOPED_TIMER(__FUNCTION__);

  m_allocator.destroyBuffer(m_bSceneInfo);

  // Create a buffer (UBO) to store the scene information
  NVVK_CHECK(m_allocator.createBuffer(m_bSceneInfo, sizeof(shaderio::SceneInfo),
                                      VK_BUFFER_USAGE_2_UNIFORM_BUFFER_BIT |
                                          VK_BUFFER_USAGE_2_TRANSFER_DST_BIT,
                                      VMA_MEMORY_USAGE_AUTO));
  NVVK_DBG_NAME(m_bSceneInfo.buffer);

  assert(m_stagingUploader.isAppendedEmpty());
  VkCommandBuffer cmd = m_app->createTempCmdBuffer();
  m_stagingUploader.cmdUploadAppended(cmd);
  m_app->submitAndWaitTempCmdBuffer(cmd);
  m_stagingUploader.releaseStaging();
}

void Raytracer::createRaytraceDescriptorLayout() {
  SCOPED_TIMER(__FUNCTION__);
  nvvk::DescriptorBindings bindings;
  bindings.addBinding({.binding = shaderio::BindingIndex::eOutImage,
                       .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
                       .descriptorCount = 1,
                       .stageFlags = VK_SHADER_STAGE_ALL});
  bindings.addBinding({.binding = shaderio::BindingIndex::eSceneDesc,
                       .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                       .descriptorCount = 1,
                       .stageFlags = VK_SHADER_STAGE_ALL});
  bindings.addBinding({.binding = shaderio::BindingIndex::eVolumeGrid,
                      .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
                      .descriptorCount = 1,
                      .stageFlags = VK_SHADER_STAGE_ALL});
  bindings.addBinding({.binding = shaderio::BindingIndex::eVolumeDesc,
                      .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                      .descriptorCount = 1,
                      .stageFlags = VK_SHADER_STAGE_ALL});
  bindings.addBinding({.binding = shaderio::BindingIndex::eHdrImage,
                      .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                      .descriptorCount = 1,
                      .stageFlags = VK_SHADER_STAGE_ALL});
  // Creating a PUSH descriptor set and set layout from the bindings
  m_rtDescPack.init(bindings, m_app->getDevice(), 0,
                    VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR);
}

void Raytracer::createRayTracingPipeline() {
  SCOPED_TIMER(__FUNCTION__);
  // For re-creation
  vkDestroyPipeline(m_app->getDevice(), m_rtPipeline, nullptr);
  vkDestroyPipelineLayout(m_app->getDevice(), m_rtPipelineLayout, nullptr);

  // Creating all shaders
  enum { eRaygen, eShaderGroupCount };
  std::array<VkPipelineShaderStageCreateInfo, eShaderGroupCount> stages{};
  for (auto &s : stages)
    s.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;

  // Use the embedded SPIR-V generated by compile_slang.
  VkShaderModuleCreateInfo shaderCode{
      VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
  shaderCode.codeSize = raytrace_slang_sizeInBytes;
  shaderCode.pCode = raytrace_slang;

  stages[eRaygen].pNext = &shaderCode;
  stages[eRaygen].pName = "rgenMain";
  stages[eRaygen].stage = VK_SHADER_STAGE_RAYGEN_BIT_KHR;

  // Shader groups
  VkRayTracingShaderGroupCreateInfoKHR group{
      VK_STRUCTURE_TYPE_RAY_TRACING_SHADER_GROUP_CREATE_INFO_KHR};
  group.anyHitShader = VK_SHADER_UNUSED_KHR;
  group.closestHitShader = VK_SHADER_UNUSED_KHR;
  group.generalShader = VK_SHADER_UNUSED_KHR;
  group.intersectionShader = VK_SHADER_UNUSED_KHR;

  std::vector<VkRayTracingShaderGroupCreateInfoKHR> shader_groups;
  // Raygen
  group.type = VK_RAY_TRACING_SHADER_GROUP_TYPE_GENERAL_KHR;
  group.generalShader = eRaygen;
  shader_groups.push_back(group);

  // // Push constant: we want to be able to update constants used by the
  // shaders const VkPushConstantRange push_constant{VK_SHADER_STAGE_ALL, 0,
  //                                         sizeof(shaderio::TutoPushConstant)};

  VkPipelineLayoutCreateInfo pipeline_layout_create_info{
      VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
  // pipeline_layout_create_info.pushConstantRangeCount = 1;
  // pipeline_layout_create_info.pPushConstantRanges = &push_constant;

  // Descriptor sets: one specific to ray tracing, and one shared with the
  // rasterization pipeline
  std::array<VkDescriptorSetLayout, 1> layouts = {{m_rtDescPack.getLayout()}};
  pipeline_layout_create_info.setLayoutCount = uint32_t(layouts.size());
  pipeline_layout_create_info.pSetLayouts = layouts.data();
  vkCreatePipelineLayout(m_app->getDevice(), &pipeline_layout_create_info,
                         nullptr, &m_rtPipelineLayout);
  NVVK_DBG_NAME(m_rtPipelineLayout);

  // Assemble the shader stages and recursion depth info into the ray tracing
  // pipeline
  VkRayTracingPipelineCreateInfoKHR rtPipelineInfo{
      VK_STRUCTURE_TYPE_RAY_TRACING_PIPELINE_CREATE_INFO_KHR};
  rtPipelineInfo.stageCount =
      static_cast<uint32_t>(stages.size()); // Stages are shaders
  rtPipelineInfo.pStages = stages.data();
  rtPipelineInfo.groupCount = static_cast<uint32_t>(shader_groups.size());
  rtPipelineInfo.pGroups = shader_groups.data();
  rtPipelineInfo.maxPipelineRayRecursionDepth = 1;
  rtPipelineInfo.layout = m_rtPipelineLayout;
  vkCreateRayTracingPipelinesKHR(m_app->getDevice(), {}, {}, 1, &rtPipelineInfo,
                                 nullptr, &m_rtPipeline);
  NVVK_DBG_NAME(m_rtPipeline);

  // Create the shader binding table for this pipeline
  createShaderBindingTable(rtPipelineInfo);
}

void Raytracer::createShaderBindingTable(
    const VkRayTracingPipelineCreateInfoKHR &rtPipelineInfo) {
  SCOPED_TIMER(__FUNCTION__);

  m_allocator.destroyBuffer(m_sbtBuffer); // Cleanup when re-creating
  // Calculate required SBT buffer size
  size_t bufferSize =
      m_sbtGenerator.calculateSBTBufferSize(m_rtPipeline, rtPipelineInfo);
  assert(bufferSize > 0 && "SBT buffer size is zero. Check pipeline groups and "
                           "SBT generator initialization.");

  // Create SBT buffer using the size from above
  NVVK_CHECK(
      m_allocator.createBuffer(m_sbtBuffer, bufferSize,
                               VK_BUFFER_USAGE_2_SHADER_BINDING_TABLE_BIT_KHR |
                                   VK_BUFFER_USAGE_2_SHADER_DEVICE_ADDRESS_BIT,
                               VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
                               VMA_ALLOCATION_CREATE_MAPPED_BIT |
                                   VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT,
                               m_sbtGenerator.getBufferAlignment()));
  NVVK_DBG_NAME(m_sbtBuffer.buffer);

  // Populate the SBT buffer with shader handles and data using the CPU-mapped
  // memory pointer
  NVVK_CHECK(m_sbtGenerator.populateSBTBuffer(m_sbtBuffer.address, bufferSize,
                                              m_sbtBuffer.mapping));
}

//---------------------------------------------------------------------------------------------------------------
// The update of scene information buffer (UBO)
//
void Raytracer::updateSceneBuffer(VkCommandBuffer cmd) {
  NVVK_DBG_SCOPE(cmd); // <-- Helps to debug in NSight
  const glm::mat4 &viewMatrix = m_cameraManip->getViewMatrix();
  const glm::mat4 &projMatrix = m_cameraManip->getPerspectiveMatrix();

  m_sceneInfo.viewProjMatrix = projMatrix * viewMatrix;
  m_sceneInfo.projInvMatrix = glm::inverse(m_cameraManip->getPerspectiveMatrix());
  m_sceneInfo.viewInvMatrix = glm::inverse(m_cameraManip->getViewMatrix());
  m_sceneInfo.cameraPosition = m_cameraManip->getEye();
  m_sceneInfo.useSky = 0;

  // Reset accumulation when the camera moves
  if (m_sceneInfo.viewInvMatrix != m_prevViewMatrix) {
    m_sceneInfo.frameIndex = 0;
    m_prevViewMatrix = m_sceneInfo.viewInvMatrix;
  }

  m_sceneInfo.frameIndex++;
  // Sync HG anisotropy (may change from UI) into VolumeDesc
  m_volumeDesc.nanoGridInfo.w = std::bit_cast<uint32_t>(m_hgG);

  // Making sure the scene information buffer is updated before rendering
  // Wait that the fragment shader is done reading the previous scene
  // information and wait for the transfer to complete
  nvvk::cmdBufferMemoryBarrier(cmd, {m_bSceneInfo.buffer,
                                     VK_PIPELINE_STAGE_2_RAY_TRACING_SHADER_BIT_KHR,
                                     VK_PIPELINE_STAGE_2_TRANSFER_BIT});
  vkCmdUpdateBuffer(cmd, m_bSceneInfo.buffer, 0, sizeof(shaderio::SceneInfo),
                    &m_sceneInfo);
  nvvk::cmdBufferMemoryBarrier(cmd, {m_bSceneInfo.buffer,
                                     VK_PIPELINE_STAGE_2_TRANSFER_BIT,
                                     VK_PIPELINE_STAGE_2_RAY_TRACING_SHADER_BIT_KHR});

  // Also keep VolumeDesc buffer in sync (densityScale / sigmaMax may change from UI)
  nvvk::cmdBufferMemoryBarrier(cmd, {m_bVolumeDesc.buffer,
                                     VK_PIPELINE_STAGE_2_RAY_TRACING_SHADER_BIT_KHR,
                                     VK_PIPELINE_STAGE_2_TRANSFER_BIT});
  vkCmdUpdateBuffer(cmd, m_bVolumeDesc.buffer, 0, sizeof(shaderio::VolumeDesc),
                    &m_volumeDesc);
  nvvk::cmdBufferMemoryBarrier(cmd, {m_bVolumeDesc.buffer,
                                     VK_PIPELINE_STAGE_2_TRANSFER_BIT,
                                     VK_PIPELINE_STAGE_2_RAY_TRACING_SHADER_BIT_KHR});
}

void Raytracer::raytrace(const VkCommandBuffer &cmd) {
  NVVK_DBG_SCOPE(cmd); // <-- Helps to debug in NSight

  // Bind the ray tracing pipeline
  vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR, m_rtPipeline);

  // Push descriptor sets for ray tracing
  nvvk::WriteSetContainer write{};
  write.append(m_rtDescPack.makeWrite(shaderio::BindingIndex::eOutImage),
               m_gBuffers.getColorImageView(), VK_IMAGE_LAYOUT_GENERAL);
  write.append(m_rtDescPack.makeWrite(shaderio::BindingIndex::eSceneDesc),
               m_bSceneInfo.buffer, VK_IMAGE_LAYOUT_UNDEFINED);
  write.append(m_rtDescPack.makeWrite(shaderio::BindingIndex::eVolumeGrid),
               m_bVolumeGrid.buffer, VK_IMAGE_LAYOUT_UNDEFINED);
  write.append(m_rtDescPack.makeWrite(shaderio::BindingIndex::eVolumeDesc),
                m_bVolumeDesc.buffer, VK_IMAGE_LAYOUT_UNDEFINED);
  write.append(m_rtDescPack.makeWrite(shaderio::BindingIndex::eHdrImage),
               VkDescriptorImageInfo{.sampler     = m_linearSampler,
                                     .imageView   = m_hdrImageView,
                                     .imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL});
  
  vkCmdPushDescriptorSetKHR(cmd, VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR,
                            m_rtPipelineLayout, 0, write.size(), write.data());

  // Ray trace
  const nvvk::SBTGenerator::Regions &regions = m_sbtGenerator.getSBTRegions();
  const VkExtent2D &size = m_app->getViewportSize();
  vkCmdTraceRaysKHR(cmd, &regions.raygen, &regions.miss, &regions.hit,
                    &regions.callable, size.width, size.height, 1);
}