import SwiftUI
import UserNotifications
import Carbon.HIToolbox

@main
struct TikunchikApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Tikunchik", image: "MenuBarIcon") {
            Button("Fix Text  ⌃⇧K") {
                ConverterLogic.fixInPlace(delay: 0.3)
            }
            Button("Fix + Switch Language  ⌃⌥Space") {
                ConverterLogic.fixInPlace(delay: 0.3, switchInputLanguage: true)
            }
            Divider()
            Toggle("Open at Login", isOn: Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.isEnabled = $0 }
            ))
            Button("Settings...") {
                appDelegate.showSetupWindow()
            }
            Divider()
            Button("Quit Tikunchik") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private enum HotKeyAction: UInt32 {
        case fixText = 1
        case fixTextAndSwitchLanguage = 2
    }

    private var setupWindow: NSWindow?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var hotKeyHandlerRef: EventHandlerRef?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let setupDone = UserDefaults.standard.bool(forKey: "setupCompleted")

        if setupDone {
            NSApp.setActivationPolicy(.accessory)
        }

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        registerHotkey()

        if !setupDone {
            showSetupWindow()
        }
    }

    func showSetupWindow() {
        if setupWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "תיקונצ'יק — הגדרות"
            window.contentViewController = NSHostingController(rootView: SetupView())
            window.center()
            setupWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func registerHotkey() {
        let eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, event, _ in
            guard let event else { return noErr }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr, let action = HotKeyAction(rawValue: hotKeyID.id) else { return noErr }

            switch action {
            case .fixText:
                ConverterLogic.fixInPlace(delay: 0.3)
            case .fixTextAndSwitchLanguage:
                ConverterLogic.fixInPlace(delay: 0.3, switchInputLanguage: true)
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            [eventSpec],
            nil,
            &hotKeyHandlerRef
        )

        registerHotKey(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(controlKey | shiftKey),
            action: .fixText
        )
        registerHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(controlKey | optionKey),
            action: .fixTextAndSwitchLanguage
        )

        registerEventMonitorFallback()
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, action: HotKeyAction) {
        let hotKeyID = EventHotKeyID(signature: OSType(0x54494B4B), id: action.rawValue)
        var hotKeyRef: EventHotKeyRef?
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
        }
    }

    private func registerEventMonitorFallback() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            Self.handleMonitoredKeyEvent(event)
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Self.handleMonitoredKeyEvent(event) {
                return nil
            }
            return event
        }
    }

    @discardableResult
    private static func handleMonitoredKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])

        if flags == [.control, .shift], event.keyCode == UInt16(kVK_ANSI_K) {
            ConverterLogic.fixInPlace(delay: 0.3)
            return true
        }

        if flags == [.control, .option], event.keyCode == UInt16(kVK_Space) {
            ConverterLogic.fixInPlace(delay: 0.3, switchInputLanguage: true)
            return true
        }

        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }

        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
