import Foundation
import IOKit.hid

struct ControlDescriptor {
    let transport: String
    let applicationUsages: [(page: UInt32, usage: UInt32)]
    let inputPages: [UInt32]

    // Seize only a separate consumer-control interface, never a keyboard or pointer.
    var isEligible: Bool {
        ["USB", "Audio"].contains(transport)
            && applicationUsages.contains { $0.page == 12 && $0.usage == 1 }
            && !applicationUsages.contains { $0.page == 1 || $0.page == 7 || $0.page == 13 }
            && !inputPages.isEmpty
            && inputPages.allSatisfy { $0 == 12 }
    }
}

struct ControlDevice {
    let handles: [IOHIDDevice]
    let id: UInt64
    let name: String
    let transport: String
}

private func physicalUSBID(_ device: IOHIDDevice) -> UInt64? {
    var entry = IOHIDDeviceGetService(device)
    IOObjectRetain(entry)
    defer { IOObjectRelease(entry) }
    while true {
        if IOObjectConformsTo(entry, "IOUSBHostDevice") != 0 {
            var id: UInt64 = 0
            return IORegistryEntryGetRegistryEntryID(entry, &id) == kIOReturnSuccess ? id : nil
        }
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
                == kIOReturnSuccess else { return nil }
        IOObjectRelease(entry)
        entry = parent
    }
}

func controlDevices() -> [ControlDevice] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 12,
                                          kIOHIDDeviceUsageKey: 1] as CFDictionary)
    let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
    let interfaces: [ControlDevice] = devices.compactMap { device in
        func property(_ key: String) -> CFTypeRef? {
            IOHIDDeviceGetProperty(device, key as CFString)
        }
        let transport = property(kIOHIDTransportKey) as? String ?? ""
        let pairs = property(kIOHIDDeviceUsagePairsKey) as? [[String: NSNumber]] ?? []
        let usages = pairs.compactMap { pair -> (page: UInt32, usage: UInt32)? in
            guard let page = pair[kIOHIDDeviceUsagePageKey],
                  let usage = pair[kIOHIDDeviceUsageKey] else { return nil }
            return (page.uint32Value, usage.uint32Value)
        }
        let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement] ?? []
        let inputPages = elements.filter {
            (1...4).contains(IOHIDElementGetType($0).rawValue)
        }.map { IOHIDElementGetUsagePage($0) }
        guard ControlDescriptor(transport: transport, applicationUsages: usages,
                                inputPages: inputPages).isEligible else { return nil }
        var id: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
                == kIOReturnSuccess else { return nil }
        return ControlDevice(handles: [device], id: physicalUSBID(device) ?? id,
                             name: property(kIOHIDProductKey) as? String ?? "USB media controls",
                             transport: transport)
    }
    return Dictionary(grouping: interfaces, by: \.id).values.map { group in
        let first = group[0]
        return ControlDevice(handles: group.flatMap(\.handles), id: first.id,
                             name: first.name, transport: first.transport)
    }.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
}

final class ButtonBlocker {
    private(set) var device: ControlDevice?
    private(set) var presses = 0
    var onPress: (() -> Void)?

    func start(_ target: ControlDevice) -> IOReturn {
        stop()
        var opened: [IOHIDDevice] = []
        for handle in target.handles {
            let result = IOHIDDeviceOpen(handle, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            guard result == kIOReturnSuccess else {
                for handle in opened { IOHIDDeviceClose(handle, 0) }
                return result
            }
            opened.append(handle)
        }
        device = target
        presses = 0
        for handle in target.handles {
            IOHIDDeviceRegisterInputValueCallback(handle, { context, result, _, value in
                guard result == kIOReturnSuccess, let context,
                      IOHIDValueGetIntegerValue(value) != 0 else { return }
                let blocker = Unmanaged<ButtonBlocker>.fromOpaque(context).takeUnretainedValue()
                blocker.presses += 1
                blocker.onPress?()
            }, Unmanaged.passUnretained(self).toOpaque())
            IOHIDDeviceScheduleWithRunLoop(handle, CFRunLoopGetMain(),
                                          CFRunLoopMode.commonModes.rawValue)
        }
        return kIOReturnSuccess
    }

    func stop() {
        guard let device else { return }
        for handle in device.handles {
            IOHIDDeviceUnscheduleFromRunLoop(handle, CFRunLoopGetMain(),
                                            CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceRegisterInputValueCallback(handle, nil, nil)
            IOHIDDeviceClose(handle, 0)
        }
        self.device = nil
    }

    deinit { stop() }
}
