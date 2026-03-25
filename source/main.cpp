#include <memory>
#include <nvapp/application.hpp>
#include <nvapp/elem_default_menu.hpp>
#include <nvapp/elem_default_title.hpp>
#include <nvvk/context.hpp>
#include <nvapp/elem_camera.hpp>

#include "peacock/raytracer.h"

using namespace peacock;

int main() {
  //--------------------------------------------------------------------------------------------------
  // Vulkan setup
  VkPhysicalDeviceShaderObjectFeaturesEXT shaderObjectFeatures{
      VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT};
  VkPhysicalDeviceAccelerationStructureFeaturesKHR accelFeature{
      VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR};
  VkPhysicalDeviceRayTracingPipelineFeaturesKHR rtPipelineFeature{
      VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_FEATURES_KHR};

  nvvk::ContextInitInfo vkSetup = {
      .instanceExtensions = {VK_EXT_DEBUG_UTILS_EXTENSION_NAME},
      .deviceExtensions =
          {
              {VK_KHR_SWAPCHAIN_EXTENSION_NAME},
              {VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME},
              {VK_KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME},
              {VK_EXT_SHADER_OBJECT_EXTENSION_NAME, &shaderObjectFeatures},
              {VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME, &accelFeature},
              {VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME, &rtPipelineFeature},
          },
      .queues = {VK_QUEUE_GRAPHICS_BIT, VK_QUEUE_TRANSFER_BIT},
  };
  nvvk::addSurfaceExtensions(vkSetup.instanceExtensions);

  // Initialize the Vulkan context
  nvvk::Context vkContext;
  if (vkContext.init(vkSetup) != VK_SUCCESS) {
    LOGE("Error in Vulkan context creation\n");
    return 1;
  }

  // Setting up the application
  nvapp::ApplicationCreateInfo appInfo{
      .name = "Ray Tracing Tutorial",
      .instance = vkContext.getInstance(),
      .device = vkContext.getDevice(),
      .physicalDevice = vkContext.getPhysicalDevice(),
      .queues = vkContext.getQueueInfos(),
  };

  auto raytracer = std::make_shared<Raytracer>();
  auto elemCamera = std::make_shared<nvapp::ElementCamera>();

  auto cameraManip = raytracer->getCameraManipulator();
  elemCamera->setCameraManipulator(cameraManip);

  // Create the application
  nvapp::Application application;
  application.init(appInfo);
  application.addElement(std::make_shared<nvapp::ElementDefaultMenu>());
  application.addElement(std::make_shared<nvapp::ElementDefaultWindowTitle>());
  application.addElement(raytracer);
  application.addElement(elemCamera);

  application.run(); // Start the application, loop until the window is closed

  application.deinit(); // Closing application

  vkContext.deinit(); // De-initialize the Vulkan context
}