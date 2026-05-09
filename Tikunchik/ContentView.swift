import SwiftUI
import AppKit
import UserNotifications

struct SetupView: View {
    @State private var accessibilityGranted = false
    @State private var notificationsGranted = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("תיקונצ'יק")
                .font(.largeTitle.bold())

            Text("מתקן טקסט שהוקלד בשפה הלא נכונה")
                .foregroundStyle(.secondary)

            Divider()

            // Usage Instructions
            VStack(alignment: .leading, spacing: 6) {
                Text("איך להשתמש:").font(.headline)
                HStack(alignment: .top, spacing: 8) {
                    Text("⌃⇧K").font(.system(.caption, design: .monospaced)).bold()
                    Text("סמן טקסט ולחץ לתיקון במקום")
                        .font(.caption)
                }
                HStack(alignment: .top, spacing: 8) {
                    Text("⌃⌥Space").font(.system(.caption, design: .monospaced)).bold()
                    Text("תיקון טקסט + החלפת שפת מקלדת")
                        .font(.caption)
                }
                HStack(alignment: .top, spacing: 8) {
                    Text("תפריט").font(.system(.caption, design: .monospaced)).bold()
                    Text("לחץ על האייקון בשורת התפריט לאפשרויות נוספות")
                        .font(.caption)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)

            Divider()

            // Accessibility
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .red)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility").font(.headline)
                        Text("נדרש לקיצור מקשים גלובלי ולתיקון טקסט במקום")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                if !accessibilityGranted {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("איך להפעיל:")
                            .font(.caption.bold())
                        Text("1. לחץ \"פתח הגדרות Accessibility\" למטה")
                            .font(.caption)
                        Text("2. לחץ על ＋ בתחתית הרשימה")
                            .font(.caption)
                        Text("3. לחץ \"הצג ב-Finder\" ואז גרור את האפליקציה לרשימה")
                            .font(.caption)
                        Text("4. ודא שהמתג דלוק")
                            .font(.caption)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 10) {
                        Button("פתח הגדרות Accessibility") {
                            openAccessibilitySettings()
                        }
                        Button("הצג ב-Finder") {
                            revealAppInFinder()
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal)

            Divider()

            // Notifications
            HStack(spacing: 12) {
                Image(systemName: notificationsGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(notificationsGranted ? .green : .red)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications").font(.headline)
                    Text("להצגת התראה כשטקסט תוקן")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !notificationsGranted {
                    Button("אפשר התראות") {
                        requestNotifications()
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal)

            Divider()

            Button(action: completeSetup) {
                Text(accessibilityGranted ? "סיום ✓" : "המשך בכל זאת")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 480, height: accessibilityGranted ? 520 : 640)
        .onAppear(perform: checkPermissions)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                checkPermissions()
            }
        }
    }

    private func checkPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                notificationsGranted = settings.authorizationStatus == .authorized
            }
        }
    }

    private func openAccessibilitySettings() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func revealAppInFinder() {
        NSWorkspace.shared.selectFile(
            Bundle.main.bundlePath,
            inFileViewerRootedAtPath: ""
        )
    }

    private func requestNotifications() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()

            if settings.authorizationStatus == .notDetermined {
                let granted = try? await center.requestAuthorization(options: [.alert, .sound])
                await MainActor.run {
                    notificationsGranted = granted == true
                }

                if granted == true {
                    return
                }
            }

            await MainActor.run {
                openNotificationSettings()
            }
        }
    }

    private func openNotificationSettings() {
        let urls = notificationSettingsURLs()
        for url in urls {
            if NSWorkspace.shared.open(url) {
                break
            }
        }
    }

    private func notificationSettingsURLs() -> [URL] {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        let rawURLs = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleIdentifier)",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        return rawURLs.compactMap(URL.init(string:))
    }

    private func completeSetup() {
        UserDefaults.standard.set(true, forKey: "setupCompleted")
        NSApp.keyWindow?.close()
        NSApp.setActivationPolicy(.accessory)
    }
}
