#ifndef RUNNER_WINDOWS_INTEGRATION_H_
#define RUNNER_WINDOWS_INTEGRATION_H_

#include <flutter/binary_messenger.h>

#include <memory>

class WindowsIntegration {
 public:
  explicit WindowsIntegration(flutter::BinaryMessenger* messenger);
  ~WindowsIntegration();

  WindowsIntegration(const WindowsIntegration&) = delete;
  WindowsIntegration& operator=(const WindowsIntegration&) = delete;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_WINDOWS_INTEGRATION_H_
