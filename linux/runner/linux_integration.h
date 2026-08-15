#ifndef RUNNER_LINUX_INTEGRATION_H_
#define RUNNER_LINUX_INTEGRATION_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <memory>

// Owns the Linux-specific global shortcut and cross-application text bridges.
// Full desktop integration (global F8, target capture, paste injection) is
// available on X11. On native Wayland the global F8 shortcuts are registered
// through the xdg-desktop-portal GlobalShortcuts interface where the
// compositor supports it, and text delivery falls back to the clipboard.
class LinuxIntegration {
 public:
  explicit LinuxIntegration(FlBinaryMessenger* messenger, GtkWindow* window);
  ~LinuxIntegration();

  LinuxIntegration(const LinuxIntegration&) = delete;
  LinuxIntegration& operator=(const LinuxIntegration&) = delete;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_LINUX_INTEGRATION_H_
