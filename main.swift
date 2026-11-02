import AppKit
import CoreGraphics
import IOKit.hid

func runChecks() {
    func descriptor(_ transport: String, _ usages: [(UInt32, UInt32)],
                    _ pages: [UInt32]) -> ControlDescriptor {
        ControlDescriptor(transport: transport, applicationUsages: usages, inputPages: pages)
    }
    let cases: [(String, ControlDescriptor, Bool)] = [
        ("USB earphone controls", descriptor("USB", [(12, 1)], [12]), true),
        ("Audio headset controls", descriptor("Audio", [(12, 1)], [12, 12, 12]), true),
        ("Keyboard with media keys", descriptor("USB", [(1, 6), (12, 1)], [7, 12]), false),
        ("Mouse with media controls", descriptor("USB", [(1, 2), (12, 1)], [1, 12]), false),
        ("Hidden keyboard input", descriptor("USB", [(12, 1)], [12, 7]), false),
        ("Internal keyboard", descriptor("FIFO", [(12, 1)], [12]), false),
        ("Bluetooth controls", descriptor("Bluetooth", [(12, 1)], [12]), false),
        ("Uninspectable device", descriptor("USB", [(12, 1)], []), false)
    ]
    for (name, value, expected) in cases {
        guard value.isEligible == expected else { fatalError("Failed: \(name)") }
        print("PASS: \(name)")
    }
}

if CommandLine.arguments.contains("--self-test") {
    runChecks()
    exit(0)
}
if CommandLine.arguments.contains("--list-devices") {
    for device in controlDevices() {
        print("\(device.name) | \(device.transport) | device \(device.id) | \(device.handles.count) control interface(s)")
    }
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let picker = NSPopUpButton()
    private let toggle = NSButton(title: "Block Buttons", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let blocker = ButtonBlocker()
    private var devices: [ControlDevice] = []
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 410),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "Earphone Silencer"
        window.center()
        window.isReleasedWhenClosed = false

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28)
        ])

        let title = NSTextField(labelWithString: "Quiet buttons. Same sound.")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        root.addArrangedSubview(title)
        let subtitle = NSTextField(wrappingLabelWithString:
            "Block the control interface of your wired earphones. Audio and the microphone stay connected.")
        subtitle.textColor = .secondaryLabelColor
        root.addArrangedSubview(subtitle)

        let caption = NSTextField(labelWithString: "EARPHONE CONTROLS")
        caption.font = .systemFont(ofSize: 10, weight: .semibold)
        caption.textColor = .secondaryLabelColor
        root.addArrangedSubview(caption)
        picker.target = self
        picker.action = #selector(selectionChanged)
        root.addArrangedSubview(picker)
        picker.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        status.font = .systemFont(ofSize: 14, weight: .medium)
        root.addArrangedSubview(status)
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 12)
        root.addArrangedSubview(detail)
        for label in [subtitle, status, detail] {
            label.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }

        toggle.bezelStyle = .rounded
        toggle.controlSize = .large
        toggle.target = self
        toggle.action = #selector(toggleBlocking)
        root.addArrangedSubview(toggle)
        let permission = NSButton(title: "Input Monitoring Settings…", target: self,
                                  action: #selector(openPermissions))
        permission.bezelStyle = .inline
        root.addArrangedSubview(permission)

        blocker.onPress = { [weak self] in self?.showBlockingState() }
        refreshDevices()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeMenu() {
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Earphone Silencer", action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        item.submenu = appMenu
        NSApp.mainMenu = menu
    }

    private func refreshDevices() {
        let found = controlDevices()
        if let active = blocker.device, !found.contains(where: { $0.id == active.id }) {
            blocker.stop()
            status.stringValue = "Earphones disconnected"
            detail.stringValue = "Reconnect your earphones, then click Block Buttons again."
        }
        let previousID = devices.indices.contains(picker.indexOfSelectedItem)
            ? devices[picker.indexOfSelectedItem].id : nil
        let changed = found.map(\.id) != devices.map(\.id)
        devices = found
        if changed || picker.numberOfItems == 0 {
            picker.removeAllItems()
            if devices.isEmpty {
                picker.addItem(withTitle: "No compatible wired controls found")
            } else {
                // Distinguish interfaces without matching all devices that share a vendor ID.
                picker.addItems(withTitles: devices.map { device in
                    let duplicates = devices.filter { $0.name == device.name && $0.transport == device.transport }
                    return duplicates.count > 1 ? "\(device.name) · \(device.id)" : "\(device.name) · \(device.transport)"
                })
                if let previousID, let index = devices.firstIndex(where: { $0.id == previousID }) {
                    picker.selectItem(at: index)
                } else if let index = devices.firstIndex(where: { $0.transport == "USB" }) {
                    picker.selectItem(at: index)
                }
            }
            if blocker.device == nil { selectionChanged() }
        }
        picker.isEnabled = !devices.isEmpty && blocker.device == nil
        toggle.isEnabled = !devices.isEmpty || blocker.device != nil
        toggle.title = blocker.device == nil ? "Block Buttons" : "Unblock Buttons"
    }

    @objc private func selectionChanged() {
        status.stringValue = devices.isEmpty ? "Connect your USB-C earphones" : "Ready to block"
        detail.stringValue = devices.isEmpty
            ? "Only separate wired button interfaces appear here. Some earphones do not expose one."
            : "Choose your earphones. Close this app to restore the buttons."
    }

    private func showBlockingState() {
        guard let device = blocker.device else { return }
        status.stringValue = "Blocking buttons on \(device.name)"
        detail.stringValue = "Button signals received: \(blocker.presses). Test play/pause and volume while audio is playing."
    }

    @objc private func toggleBlocking() {
        if blocker.device != nil {
            blocker.stop()
            selectionChanged()
        } else if devices.indices.contains(picker.indexOfSelectedItem) {
            let target = devices[picker.indexOfSelectedItem]
            let result = blocker.start(target)
            if result == kIOReturnSuccess {
                showBlockingState()
            } else {
                // Some drivers allow exclusive access without Input Monitoring.
                // Request it only after access actually fails, following the user's click.
                if !CGPreflightListenEventAccess() {
                    _ = CGRequestListenEventAccess()
                }
                status.stringValue = "macOS could not block this interface"
                let error = String(format: "0x%08x", UInt32(bitPattern: result))
                detail.stringValue = "Enable Earphone Silencer in Input Monitoring, then quit and reopen it. If already enabled, another app may own the controls, or this device may not support blocking. (\(error))"
            }
        }
        picker.isEnabled = blocker.device == nil && !devices.isEmpty
        toggle.title = blocker.device == nil ? "Block Buttons" : "Unblock Buttons"
    }

    @objc private func openPermissions() {
        NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        blocker.stop()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
