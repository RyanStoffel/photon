import Foundation
import IOKit
import IOKit.hidsystem

/// Toggles the Caps Lock lock state through IOHIDSystem. Needed because the physical key is
/// remapped to F18 while the Hyper key is enabled.
enum CapsLockState {
  static func toggle() {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    guard service != 0 else {
      return
    }
    defer { IOObjectRelease(service) }

    var connect: io_connect_t = 0
    guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else {
      return
    }
    defer { IOServiceClose(connect) }

    var state = false
    guard IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &state) == KERN_SUCCESS else {
      return
    }
    IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), !state)
  }
}
