#include "renderer.h"
#include "common.h"

#include <array>
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include <stb_image_write.h>
#define TINYOBJLOADER_IMPLEMENTATION
#include <tiny_obj_loader.h>

PushConstants pushConstants{800 /* render_width */, 600 /* render_height */};

VkCommandBuffer AllocateAndBeginOneTimeCommandBuffer(VkDevice device, VkCommandPool commandPool)
{
  // allocate info
  auto cmdAllocateInfo = nvvk::make<VkCommandBufferAllocateInfo>();
  cmdAllocateInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
  cmdAllocateInfo.commandPool = commandPool;
  cmdAllocateInfo.commandBufferCount = 1;

  // allocate command buffer
  VkCommandBuffer cmdBuffer;
  NVVK_CHECK(vkAllocateCommandBuffers(device, &cmdAllocateInfo, &cmdBuffer));

  // begin recording
  auto cmdBeginInfo = nvvk::make<VkCommandBufferBeginInfo>();
  cmdBeginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  NVVK_CHECK(vkBeginCommandBuffer(cmdBuffer, &cmdBeginInfo));

  return cmdBuffer;
}

void EndSubmitWaitAndFreeCommandBuffer(VkDevice device, VkQueue queue, VkCommandPool cmdPool, VkCommandBuffer cmdBuffer)
{
  // end recording
  NVVK_CHECK(vkEndCommandBuffer(cmdBuffer));

  // submit command buffer
  auto submitInfo = nvvk::make<VkSubmitInfo>();
  submitInfo.commandBufferCount = 1;
  submitInfo.pCommandBuffers = &cmdBuffer;
  NVVK_CHECK(vkQueueSubmit(queue, 1, &submitInfo, VK_NULL_HANDLE));

  // wait for the GPU to finish
  NVVK_CHECK(vkQueueWaitIdle(queue));

  // free command buffer
  vkFreeCommandBuffers(device, cmdPool, 1, &cmdBuffer);
}

VkDeviceAddress GetBufferDeviceAddress(VkDevice device, VkBuffer buffer)
{
  auto addressInfo = nvvk::make<VkBufferDeviceAddressInfo>();
  addressInfo.buffer = buffer;
  return vkGetBufferDeviceAddress(device, &addressInfo);
}

Renderer::Renderer()
{
  // vulkan context info
  nvvk::ContextCreateInfo deviceInfo;
  // specify the version
  deviceInfo.apiMajor = 1;
  deviceInfo.apiMinor = 2;  
  // required by KHR_acceleration_structure
  deviceInfo.addDeviceExtension(VK_KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME);
  // acceleration structure extension
  auto asFeatures = nvvk::make<VkPhysicalDeviceAccelerationStructureFeaturesKHR>();
  deviceInfo.addDeviceExtension(VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME, false, &asFeatures);
  // ray query extension
  auto rayQueryFeatures = nvvk::make<VkPhysicalDeviceRayQueryFeaturesKHR>();
  deviceInfo.addDeviceExtension(VK_KHR_RAY_QUERY_EXTENSION_NAME, false, &rayQueryFeatures);

  // create vulkan context
  m_context.init(deviceInfo);

  // create resource allocator
  m_allocator.init(m_context, m_context.m_physicalDevice);

  // create command pool
  auto cmdPoolInfo = nvvk::make<VkCommandPoolCreateInfo>();
  cmdPoolInfo.queueFamilyIndex = m_context.m_queueGCT;
  NVVK_CHECK(vkCreateCommandPool(m_context, &cmdPoolInfo, nullptr, &m_cmdPool));

  // create ray tracing builder
  m_raytracingBuilder.setup(m_context, &m_allocator, m_context.m_queueGCT);

  // create descriptor set container
  m_descriptorSetContainer.init(m_context);
}

Renderer::~Renderer()
{
  vkDestroyPipeline(m_context, m_computePipeline, nullptr);
  vkDestroyShaderModule(m_context, m_raytraceModule, nullptr);
  m_descriptorSetContainer.deinit();
  vkDestroyCommandPool(m_context, m_cmdPool, nullptr);
  m_raytracingBuilder.destroy();


  m_allocator.destroy(m_objModel.vertexBuffer);
  m_allocator.destroy(m_objModel.indexBuffer);
  m_allocator.destroy(m_buffer);
  m_allocator.deinit();

  m_context.deinit();
}

void Renderer::createBuffer()
{
    // create a framebuffer
    auto bufferCreateInfo = nvvk::make<VkBufferCreateInfo>();
    bufferCreateInfo.size = pushConstants.render_width * pushConstants.render_height * 3 * sizeof(float);
    bufferCreateInfo.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    // HOST_VISIBLE means that the CPU can read this buffer's memory.
    // HOST_CACHED means that the CPU caches this memory.
    // HOST_COHERENT means that the CPU side of cache management
    m_buffer = m_allocator.createBuffer(bufferCreateInfo, 
                                        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | 
                                        VK_MEMORY_PROPERTY_HOST_CACHED_BIT | 
                                        VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
}

void Renderer::loadModel(const std::string& filename, const std::vector<std::string>& searchPaths)
{
  tinyobj::ObjReader reader;
  reader.ParseFromFile(nvh::findFile(filename, searchPaths));
  assert(reader.Valid());  // Make sure tinyobj was able to parse this file

  const auto objVertices = reader.GetAttrib().GetVertices();

  const auto& objShapes = reader.GetShapes();
  assert(objShapes.size() == 1);
  std::vector<uint32_t> objIndices;
  objIndices.reserve(objShapes[0].mesh.indices.size());
  for (const auto& index : objShapes[0].mesh.indices)
  {
    objIndices.push_back(index.vertex_index);
  }

  // start a cmd to upload data to the GPU
  auto uploadCmdBuffer = AllocateAndBeginOneTimeCommandBuffer(m_context, m_cmdPool);
  // upload data to GPU
  const VkBufferUsageFlags usage = VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT
                                    | VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR;
  m_objModel.vertexBuffer = m_allocator.createBuffer(uploadCmdBuffer, objVertices, usage);
  m_objModel.indexBuffer = m_allocator.createBuffer(uploadCmdBuffer, objIndices, usage);
  m_objModel.numIndices = static_cast<uint32_t>(objIndices.size());
  m_objModel.numVertices = static_cast<uint32_t>(objVertices.size());
  // submit, wait, and free cmd
  EndSubmitWaitAndFreeCommandBuffer(m_context, m_context.m_queueGCT, m_cmdPool, uploadCmdBuffer);
  // finalize and release staging resources
  m_allocator.finalizeAndReleaseStaging();
}

void Renderer::createBottomLevelAS()
{
  nvvk::RaytracingBuilderKHR::BlasInput blas;

  auto triangles = nvvk::make<VkAccelerationStructureGeometryTrianglesDataKHR>();
  triangles.vertexFormat = VK_FORMAT_R32G32B32_SFLOAT;
  triangles.vertexData.deviceAddress = GetBufferDeviceAddress(m_context, m_objModel.vertexBuffer.buffer);
  triangles.vertexStride = sizeof(float) * 3;
  triangles.maxVertex = static_cast<uint32_t>(m_objModel.numVertices / 3);
  triangles.indexType = VK_INDEX_TYPE_UINT32;
  triangles.indexData.deviceAddress = GetBufferDeviceAddress(m_context, m_objModel.indexBuffer.buffer);
  triangles.transformData.deviceAddress = 0;  // No transform

  auto geometry = nvvk::make<VkAccelerationStructureGeometryKHR>();
  geometry.geometryType = VK_GEOMETRY_TYPE_TRIANGLES_KHR;
  geometry.flags = VK_GEOMETRY_OPAQUE_BIT_KHR;
  geometry.geometry.triangles = triangles;
  blas.asGeometry.emplace_back(geometry);

  VkAccelerationStructureBuildRangeInfoKHR offsetInfo;
  offsetInfo.primitiveCount = static_cast<uint32_t>(m_objModel.numIndices / 3);
  offsetInfo.primitiveOffset = 0;
  offsetInfo.firstVertex = 0;
  offsetInfo.transformOffset = 0;
  blas.asBuildOffsetInfo.emplace_back(offsetInfo);

  m_blases.emplace_back(blas);
  
  m_raytracingBuilder.buildBlas(m_blases, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR
                                          | VK_BUILD_ACCELERATION_STRUCTURE_ALLOW_COMPACTION_BIT_KHR);
}

void Renderer::createTopLevelAS()
{
  for (size_t i = 0; i < m_blases.size(); i++)
  {
    VkAccelerationStructureInstanceKHR instance{};
    instance.accelerationStructureReference = m_raytracingBuilder.getBlasDeviceAddress(static_cast<uint32_t>(i));
    instance.transform.matrix[0][0] = 1.f;
    instance.transform.matrix[1][1] = 1.f;
    instance.transform.matrix[2][2] = 1.f;
    instance.instanceCustomIndex = 0;
    instance.mask = 0xFF;
    instance.instanceShaderBindingTableRecordOffset = 0;
    instance.flags = VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR;

    m_instances.emplace_back(instance);
  }

  m_raytracingBuilder.buildTlas(m_instances, VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR);
}

void Renderer::loadShader(const std::string& filename, const std::vector<std::string>& searchPaths)
{
  // create raytrace module
  m_raytraceModule = nvvk::createShaderModule(m_context, nvh::loadFile("shaders/raytrace.comp.glsl.spv", true, searchPaths, true));
}

void Renderer::createComputePipeline()
{
  // create shader stage
  auto shaderStageCreateInfo = nvvk::make<VkPipelineShaderStageCreateInfo>();
  shaderStageCreateInfo.stage = VK_SHADER_STAGE_COMPUTE_BIT;
  shaderStageCreateInfo.module = m_raytraceModule;
  shaderStageCreateInfo.pName = "main";

  // list binding
  m_descriptorSetContainer.addBinding(BINDING_IMAGEDATA, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT);
  m_descriptorSetContainer.addBinding(BINDING_TLAS, VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR, 1, VK_SHADER_STAGE_COMPUTE_BIT);
  m_descriptorSetContainer.addBinding(BINDING_VERTICES, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT);
  m_descriptorSetContainer.addBinding(BINDING_INDICES, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT);

  // create descriptor set layout
  m_descriptorSetContainer.initLayout();

  // create descriptor pool and allocate descriptor set
  m_descriptorSetContainer.initPool(1);

  // create pipeline layout from descriptor set layout
  static_assert(sizeof(PushConstants) % 4 == 0, "Push constant size must be a multiple of 4 per the Vulkan spec!");
  VkPushConstantRange pushConstantRange;
  pushConstantRange.stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
  pushConstantRange.offset = 0;
  pushConstantRange.size = sizeof(PushConstants);

  m_descriptorSetContainer.initPipeLayout(1, &pushConstantRange);

  // create pipeline
  auto pipelineCreateInfo = nvvk::make<VkComputePipelineCreateInfo>();
  pipelineCreateInfo.stage = shaderStageCreateInfo;
  pipelineCreateInfo.layout = m_descriptorSetContainer.getPipeLayout();

  NVVK_CHECK(vkCreateComputePipelines(m_context, VK_NULL_HANDLE, 1, &pipelineCreateInfo, VK_NULL_HANDLE, &m_computePipeline));
}

void Renderer::updateDescriptorSet()
{
  std::vector<VkWriteDescriptorSet> writeDescriptorSets(4);

  VkDescriptorBufferInfo descriptorBufferInfo{};
  descriptorBufferInfo.buffer = m_buffer.buffer;
  descriptorBufferInfo.range = pushConstants.render_width * pushConstants.render_height * 3 * sizeof(float);
  writeDescriptorSets[0] = m_descriptorSetContainer.makeWrite(0, 0, &descriptorBufferInfo);
  
  auto descriptorAS = nvvk::make<VkWriteDescriptorSetAccelerationStructureKHR>();
  auto tlasCopy = m_raytracingBuilder.getAccelerationStructure();
  descriptorAS.accelerationStructureCount = 1;
  descriptorAS.pAccelerationStructures = &tlasCopy;
  writeDescriptorSets[1] = m_descriptorSetContainer.makeWrite(0, 1, &descriptorAS);
  
  VkDescriptorBufferInfo vertexDescriptorBufferInfo{};
  vertexDescriptorBufferInfo.buffer = m_objModel.vertexBuffer.buffer;
  vertexDescriptorBufferInfo.range = VK_WHOLE_SIZE;
  writeDescriptorSets[2] = m_descriptorSetContainer.makeWrite(0, 2, &vertexDescriptorBufferInfo);

  VkDescriptorBufferInfo indexDescriptorBufferInfo{};
  indexDescriptorBufferInfo.buffer = m_objModel.indexBuffer.buffer;
  indexDescriptorBufferInfo.range = VK_WHOLE_SIZE;
  writeDescriptorSets[3] = m_descriptorSetContainer.makeWrite(0, 3, &indexDescriptorBufferInfo);

  // update descriptor set
  vkUpdateDescriptorSets(m_context, static_cast<uint32_t>(writeDescriptorSets.size()), writeDescriptorSets.data(), 0, nullptr);
}

void Renderer::rayTrace()
{
  const uint32_t NUM_SAMPLE_BATCHES = 32;
  for (uint32_t sampleBatch = 0; sampleBatch < NUM_SAMPLE_BATCHES; sampleBatch++)
  {    
    // start cmd to dispatch compute shader
    auto cmdBuffer = AllocateAndBeginOneTimeCommandBuffer(m_context, m_cmdPool);

    // bind pipeline
    vkCmdBindPipeline(cmdBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_computePipeline);

    // bind descriptor set
    auto descriptorSet = m_descriptorSetContainer.getSet(0);
    vkCmdBindDescriptorSets(cmdBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_descriptorSetContainer.getPipeLayout(), 0, 1, &descriptorSet, 0, nullptr);

    // push constants
    pushConstants.sample_batch = sampleBatch;
    vkCmdPushConstants(cmdBuffer, m_descriptorSetContainer.getPipeLayout(), VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(PushConstants), &pushConstants);

    // run compute shader
    vkCmdDispatch(cmdBuffer, (pushConstants.render_width - 1) / WORKGROUP_WIDTH + 1, (pushConstants.render_height - 1) / WORKGROUP_HEIGHT + 1, 1);

    // memory barrier
    if (sampleBatch == NUM_SAMPLE_BATCHES - 1)
    {
      auto memoryBarrier = nvvk::make<VkMemoryBarrier>();
      memoryBarrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
      memoryBarrier.dstAccessMask = VK_ACCESS_HOST_READ_BIT;
      vkCmdPipelineBarrier(cmdBuffer, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_HOST_BIT, 0, 1, &memoryBarrier, 0, nullptr, 0, nullptr);
    }

    // submit, wait, and free cmd
    EndSubmitWaitAndFreeCommandBuffer(m_context, m_context.m_queueGCT, m_cmdPool, cmdBuffer);

    nvprintf("Rendered sample batch index %d.\n", sampleBatch);
  }
}

void Renderer::saveImage(const std::string& fileName)
{
  void* data = m_allocator.map(m_buffer);
  stbi_flip_vertically_on_write(1);
  stbi_write_hdr(fileName.c_str(), pushConstants.render_width, pushConstants.render_height, 3, reinterpret_cast<float*>(data));
  m_allocator.unmap(m_buffer);
}
