#define VMA_DYNAMIC_VULKAN_FUNCTIONS                                           \
  1 // Use dynamic Vulkan functions for VMA (Vulkan Memory Allocator)
#define VMA_IMPLEMENTATION // Implementation of the Vulkan Memory Allocator
#define VMA_LEAK_LOG_FORMAT(format, ...)                                       \
  {                                                                            \
    printf((format), __VA_ARGS__);                                             \
    printf("\n");                                                              \
  }

#include "peacock/raytracer.h"

#include <nvvk/check_error.hpp>
#include <nvvk/debug_util.hpp>
#include <nvvk/formats.hpp>

#include "peacock/_autogen/raytrace.slang.h"
#include "peacock/common/path_utils.h"

using namespace peacock;

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
  VkSampler linearSampler{};
  NVVK_CHECK(m_samplerPool.acquireSampler(linearSampler));
  NVVK_DBG_NAME(linearSampler);

  // Create the G-Buffers
  nvvk::GBufferInitInfo gBufferInit{
      .allocator = &m_allocator,
      .colorFormats = {VK_FORMAT_R8G8B8A8_UNORM},
      .depthFormat = nvvk::findDepthFormat(m_app->getPhysicalDevice()),
      .imageSampler = linearSampler,
      .descriptorPool = m_app->getTextureDescriptorPool(),
  };
  m_gBuffers.init(gBufferInit);

  // Initialize SBT generator with queried ray tracing properties.
  m_sbtGenerator.init(m_app->getDevice(), m_rtProperties);

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

  m_rtDescPack.deinit();
  m_gBuffers.deinit();
  m_samplerPool.deinit();
  m_stagingUploader.deinit();
  m_sbtGenerator.deinit();
  m_allocator.deinit();
}

void Raytracer::onResize(VkCommandBuffer cmd, const VkExtent2D &size) {
  NVVK_CHECK(m_gBuffers.update(cmd, size));
}

void Raytracer::onUIRender() {
  // [optional] convenient setting panel
  ImGui::Begin("Settings");
  ImGui::TextDisabled("%d FPS / %.3fms",
                      static_cast<int>(ImGui::GetIO().Framerate),
                      1000.F / ImGui::GetIO().Framerate);
  ImGui::End();

  // Rendered image displayed fully in 'Viewport' window
  ImGui::Begin("Viewport");
  ImGui::Image(ImTextureID(m_gBuffers.getDescriptorSet()),
               ImGui::GetContentRegionAvail());
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

  m_sceneInfo.viewProjMatrix =
      projMatrix * viewMatrix; // Combine the view and projection matrices
  m_sceneInfo.projInvMatrix =
      glm::inverse(projMatrix); // Inverse projection matrix
  m_sceneInfo.viewInvMatrix = glm::inverse(viewMatrix); // Inverse view matrix

  // Making sure the scene information buffer is updated before rendering
  // Wait that the fragment shader is done reading the previous scene
  // information and wait for the transfer to complete
  nvvk::cmdBufferMemoryBarrier(cmd, {m_bSceneInfo.buffer,
                                     VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
                                     VK_PIPELINE_STAGE_2_TRANSFER_BIT});
  vkCmdUpdateBuffer(cmd, m_bSceneInfo.buffer, 0, sizeof(shaderio::SceneInfo),
                    &m_sceneInfo);
  nvvk::cmdBufferMemoryBarrier(cmd, {m_bSceneInfo.buffer,
                                     VK_PIPELINE_STAGE_2_TRANSFER_BIT,
                                     VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT});
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
  vkCmdPushDescriptorSetKHR(cmd, VK_PIPELINE_BIND_POINT_RAY_TRACING_KHR,
                            m_rtPipelineLayout, 0, write.size(), write.data());

  // Ray trace
  const nvvk::SBTGenerator::Regions &regions = m_sbtGenerator.getSBTRegions();
  const VkExtent2D &size = m_app->getViewportSize();
  vkCmdTraceRaysKHR(cmd, &regions.raygen, &regions.miss, &regions.hit,
                    &regions.callable, size.width, size.height, 1);
}