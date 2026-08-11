#ifndef RUNNER_LINUX_INTEGRATION_H_
#define RUNNER_LINUX_INTEGRATION_H_

#include <flutter_linux/flutter_linux.h>

#include <memory>

// Owns the Linux-specific global shortcut and cross-application text bridges.
// Full desktop integration is available on X11. Wayland intentionally falls
// back to the Flutter UI and clipboard because compositors do not allow apps to
// capture arbitrary global keys or focus/inject into another client's window.
class LinuxIntegration {
 public:
  explicit LinuxIntegration(FlBinaryMessenger* messenger);
  ~LinuxIntegration();

  LinuxIntegration(const LinuxIntegration&) = delete;
  LinuxIntegration& operator=(const LinuxIntegration&) = delete;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_LINUX_INTEGRATION_H_
