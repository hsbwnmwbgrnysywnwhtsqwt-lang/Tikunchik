import AppKit
import Carbon.HIToolbox
import UserNotifications

enum ConverterLogic {
    private struct ConversionResult {
        let text: String
    }

    private struct FocusedTextContext {
        let element: AXUIElement
        let fullText: String
        let selectedRange: CFRange

        var textToFix: String {
            guard selectedRange.length > 0 else { return fullText }

            let nsText = fullText as NSString
            let range = NSRange(location: selectedRange.location, length: selectedRange.length)
            guard NSMaxRange(range) <= nsText.length else { return fullText }
            return nsText.substring(with: range)
        }
    }

    private static let mapping: [Character: Character] = [
        "q": "/", "w": "'", "e": "ק", "r": "ר", "t": "א",
        "y": "ט", "u": "ו", "i": "ן", "o": "ם", "p": "פ",
        "[": "]", "]": "[",
        "a": "ש", "s": "ד", "d": "ג", "f": "כ", "g": "ע",
        "h": "י", "j": "ח", "k": "ל", "l": "ך", ";": "ף",
        "'": ",",
        "z": "ז", "x": "ס", "c": "ב", "v": "ה", "b": "נ",
        "n": "מ", "m": "צ", ",": "ת", ".": "ץ", "/": ".",
    ]
    private static let reverseMapping: [Character: Character] = Dictionary(
        uniqueKeysWithValues: mapping.map { ($1, $0) }
    )

    private static var isProcessing = false
    private static var processingStartTime: Date?

    static func fixInPlace(delay: TimeInterval = 0) {
        fixInPlace(delay: delay, switchInputLanguage: false)
    }

    static func fixInPlace(delay: TimeInterval = 0, switchInputLanguage: Bool) {
        if isProcessing {
            if let start = processingStartTime, Date().timeIntervalSince(start) > 5 {
                isProcessing = false
            } else {
                return
            }
        }
        isProcessing = true
        processingStartTime = Date()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
            defer {
                isProcessing = false
                processingStartTime = nil
            }
            performFixInPlace(switchInputLanguage: switchInputLanguage)
        }
    }

    @discardableResult
    static func processClipboard() -> Bool {
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string), !text.isEmpty else { return false }
        let converted = normalizedText(from: text)
        guard converted.text != text else { return false }
        pb.clearContents()
        pb.setString(converted.text, forType: .string)
        postNotification(converted.text)
        return true
    }

    // MARK: - In-Place Fix

    private static func performFixInPlace(switchInputLanguage: Bool) {
        if let context = focusedTextContext() {
            if context.selectedRange.length == 0 {
                _ = performClipboardReplacement(
                    requireSelectAll: true,
                    switchInputLanguage: switchInputLanguage
                )
                return
            }

            let originalText = context.textToFix
            let converted = normalizedText(from: originalText)
            guard converted.text != originalText else { return }
            if replaceText(in: context, with: converted.text) {
                if switchInputLanguage {
                    DispatchQueue.main.async { switchToNextKeyboardInputSource() }
                }
                postNotification(converted.text)
                return
            }

            if performClipboardReplacement(
                requireSelectAll: context.selectedRange.length == 0,
                switchInputLanguage: switchInputLanguage
            ) {
                return
            }
        }

        if focusedTextElement() != nil {
            _ = performClipboardReplacement(requireSelectAll: true, switchInputLanguage: switchInputLanguage)
            return
        }

        _ = performClipboardReplacement(requireSelectAll: false, switchInputLanguage: switchInputLanguage)
    }

    @discardableResult
    private static func performClipboardReplacement(
        requireSelectAll: Bool,
        switchInputLanguage: Bool
    ) -> Bool {
        let pb = NSPasteboard.general
        let savedClipboard = pb.string(forType: .string)
        let changeCount = pb.changeCount

        if requireSelectAll {
            simulateKeystroke(keyCode: 0, flags: .maskCommand) // Cmd+A
            Thread.sleep(forTimeInterval: 0.08)
        }

        simulateKeystroke(keyCode: 8, flags: .maskCommand) // Cmd+C
        Thread.sleep(forTimeInterval: 0.1)

        guard pb.changeCount != changeCount else { return false }

        guard let text = pb.string(forType: .string), !text.isEmpty else {
            restore(savedClipboard)
            return false
        }

        let converted = normalizedText(from: text)
        guard converted.text != text else {
            restore(savedClipboard)
            return false
        }

        pb.clearContents()
        pb.setString(converted.text, forType: .string)

        simulateKeystroke(keyCode: 9, flags: .maskCommand) // Cmd+V
        Thread.sleep(forTimeInterval: 0.1)

        restore(savedClipboard)

        if switchInputLanguage {
            DispatchQueue.main.async { switchToNextKeyboardInputSource() }
        }

        postNotification(converted.text)
        return true
    }

    // MARK: - Keyboard Simulation

    private static func simulateKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: CGEventTapLocation.cghidEventTap)
        up?.post(tap: CGEventTapLocation.cghidEventTap)
    }

    // MARK: - Conversion

    private static func checkSpelling(of text: String, language: String) -> Bool {
        let work = { () -> Bool in
            let range = NSSpellChecker.shared.checkSpelling(
                of: text, startingAt: 0, language: language,
                wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
            )
            return range.location == NSNotFound
        }
        if Thread.isMainThread {
            return work()
        }
        var result = false
        DispatchQueue.main.sync { result = work() }
        return result
    }

    private static func isEnglishWord(_ token: String) -> Bool {
        let stripped = token.trimmingCharacters(in: .punctuationCharacters)
        guard stripped.count >= 2 else { return false }
        return checkSpelling(of: stripped, language: "en")
    }

    private static func isHebrewWord(_ token: String) -> Bool {
        let stripped = token.trimmingCharacters(in: .punctuationCharacters)
        guard stripped.count >= 2 else { return false }
        return checkSpelling(of: stripped, language: "he")
    }

    private static func normalizedText(from text: String) -> ConversionResult {
        convertText(text)
    }

    private static func convertText(_ text: String) -> ConversionResult {
        var parts: [(text: String, isWord: Bool)] = []
        var word = ""
        for char in text {
            if char.isWhitespace {
                if !word.isEmpty {
                    parts.append((word, true))
                    word = ""
                }
                parts.append((String(char), false))
            } else {
                word.append(char)
            }
        }
        if !word.isEmpty {
            parts.append((word, true))
        }

        let wordParts = parts.filter(\.isWord)
        var clearConvertCount = 0

        for part in wordParts {
            let script = dominantScript(in: part.text)
            switch script {
            case .latin:
                let hebrew = mapCharacters(in: part.text, using: mapping)
                if isHebrewWord(hebrew) || !isEnglishWord(part.text) {
                    clearConvertCount += 1
                }
            case .hebrew:
                if !isHebrewWord(part.text) {
                    clearConvertCount += 1
                }
            case .unknown:
                break
            }
        }

        let majorityConverting = clearConvertCount > wordParts.count / 2

        var result = ""
        for part in parts {
            guard part.isWord else {
                result += part.text
                continue
            }

            let script = dominantScript(in: part.text)
            switch script {
            case .latin:
                let hebrew = mapCharacters(in: part.text, using: mapping)
                if isHebrewWord(hebrew) || !isEnglishWord(part.text) || majorityConverting {
                    result += hebrew
                } else {
                    result += part.text
                }
            case .hebrew:
                if isHebrewWord(part.text) {
                    result += part.text
                } else {
                    result += mapCharacters(in: part.text, using: reverseMapping)
                }
            case .unknown:
                result += part.text
            }
        }

        return ConversionResult(text: result)
    }

    // MARK: - Helpers

    private static func focusedTextContext() -> FocusedTextContext? {
        guard
            let focusedElement = focusedTextElement(),
            let fullText = copyAttribute(kAXValueAttribute as CFString, from: focusedElement) as? String,
            !fullText.isEmpty,
            isEditableTextElement(focusedElement)
        else {
            return nil
        }

        let selectedRange = copySelectedRange(from: focusedElement) ?? CFRange(location: 0, length: 0)
        return FocusedTextContext(
            element: focusedElement,
            fullText: fullText,
            selectedRange: selectedRange
        )
    }

    private static func focusedTextElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        guard
            let focusedElement = copyElementAttribute(
                kAXFocusedUIElementAttribute as CFString,
                from: systemWideElement
            ),
            isTextElement(focusedElement)
        else {
            return nil
        }
        return focusedElement
    }

    private static func replaceText(in context: FocusedTextContext, with replacement: String) -> Bool {
        let nsText = context.fullText as NSString
        let selection = NSRange(location: context.selectedRange.location, length: context.selectedRange.length)
        guard NSMaxRange(selection) <= nsText.length else { return false }

        let updatedText: String
        let replacementRange: CFRange

        if context.selectedRange.length > 0 {
            updatedText = nsText.replacingCharacters(in: selection, with: replacement)
            replacementRange = CFRange(location: context.selectedRange.location, length: (replacement as NSString).length)
        } else {
            updatedText = replacement
            replacementRange = CFRange(location: 0, length: (replacement as NSString).length)
        }

        guard setAttribute(kAXValueAttribute as CFString, value: updatedText as CFTypeRef, on: context.element) else {
            return false
        }

        _ = setSelectedRange(replacementRange, on: context.element)
        return true
    }

    private static func isEditableTextElement(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        )
        guard status == .success, settable.boolValue else { return false }
        return isTextElement(element)
    }

    private static func isTextElement(_ element: AXUIElement) -> Bool {
        guard let role = copyAttribute(kAXRoleAttribute as CFString, from: element) as? String else {
            return false
        }

        let supportedRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ]
        return supportedRoles.contains(role)
    }

    private static func dominantScript(in token: String) -> TokenScript {
        var latinCount = 0
        var hebrewCount = 0

        for scalar in token.unicodeScalars {
            if CharacterSet.letters.contains(scalar) {
                if isHebrewScalar(scalar) {
                    hebrewCount += 1
                } else if isLatinScalar(scalar) {
                    latinCount += 1
                }
            }
        }

        if latinCount == 0, hebrewCount == 0 {
            return .unknown
        }

        return hebrewCount > latinCount ? .hebrew : .latin
    }

    private static func mapCharacters(in token: String, using table: [Character: Character]) -> String {
        String(token.map { character in
            let lowercased = Character(character.lowercased())
            let mapped = table[lowercased] ?? character
            return character.isUppercase ? Character(String(mapped).uppercased()) : mapped
        })
    }

    private static func isHebrewScalar(_ scalar: UnicodeScalar) -> Bool {
        (0x0590...0x05FF).contains(scalar.value) || (0xFB1D...0xFB4F).contains(scalar.value)
    }

    private static func isLatinScalar(_ scalar: UnicodeScalar) -> Bool {
        (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value)
    }

    private static func switchToNextKeyboardInputSource() {
        guard let cfSources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return }
        let count = CFArrayGetCount(cfSources)
        guard count > 0 else { return }

        var selectableSources: [TISInputSource] = []
        for i in 0..<count {
            guard let ptr = CFArrayGetValueAtIndex(cfSources, i) else { continue }
            let source = Unmanaged<TISInputSource>.fromOpaque(ptr).takeUnretainedValue()
            if isSelectableInputSource(source) {
                selectableSources.append(source)
            }
        }
        guard selectableSources.count > 1 else { return }

        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let currentID = inputSourceID(for: current)
        let currentIndex = selectableSources.firstIndex { inputSourceID(for: $0) == currentID } ?? -1
        let nextIndex = (currentIndex + 1) % selectableSources.count
        TISSelectInputSource(selectableSources[nextIndex])
    }

    private static func inputSourceID(for source: TISInputSource) -> String? {
        guard let sourceIDPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return unsafeBitCast(sourceIDPointer, to: CFString.self) as String
    }

    private static func isSelectableInputSource(_ source: TISInputSource) -> Bool {
        guard let categoryPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) else {
            return false
        }
        let category = unsafeBitCast(categoryPointer, to: CFString.self) as String
        let validCategories: Set<String> = [
            kTISCategoryKeyboardInputSource as String,
            "TISCategoryKeyboardInputMode"
        ]
        guard validCategories.contains(category) else { return false }

        guard let selectablePointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else {
            return false
        }
        let selectable = unsafeBitCast(selectablePointer, to: CFBoolean.self)
        return selectable == kCFBooleanTrue
    }

    private static func copySelectedRange(from element: AXUIElement) -> CFRange? {
        guard let axValue = copyAXValueAttribute(kAXSelectedTextRangeAttribute as CFString, from: element) else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private static func setSelectedRange(_ range: CFRange, on element: AXUIElement) -> Bool {
        var mutableRange = range
        guard let axValue = AXValueCreate(.cfRange, &mutableRange) else { return false }
        return setAttribute(kAXSelectedTextRangeAttribute as CFString, value: axValue, on: element)
    }

    private static func copyAttribute(_ attribute: CFString, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return nil }
        return value
    }

    private static func copyElementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success, let value else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func copyAXValueAttribute(_ attribute: CFString, from element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success, let value else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }

    private static func setAttribute(_ attribute: CFString, value: CFTypeRef, on element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, attribute, value) == .success
    }

    private static func restore(_ saved: String?) {
        guard let saved = saved else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(saved, forType: .string)
    }

    private static func postNotification(_ text: String) {
        let content = UNMutableNotificationContent()
        content.title = "תיקונצ'יק"
        let preview = text.prefix(80)
        content.body = "תוקן: \(preview)\(text.count > 80 ? "…" : "")"
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}

private enum TokenScript {
    case latin
    case hebrew
    case unknown
}

private extension NSString {
    func enumerateWordRanges() -> [NSRange] {
        var ranges: [NSRange] = []
        enumerateSubstrings(
            in: NSRange(location: 0, length: length),
            options: [.byWords, .substringNotRequired]
        ) { _, range, _, _ in
            ranges.append(range)
        }
        return ranges
    }
}
