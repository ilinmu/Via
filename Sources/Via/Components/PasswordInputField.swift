import AppKit
import SwiftUI
import ViaCore

struct PasswordInputField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isSecure: Bool
    var accessibilityLabel: String? = nil

    func makeCoordinator() -> PasswordFieldCoordinator {
        PasswordFieldCoordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField: NSTextField = isSecure
            ? PasteEnabledSecureTextField(string: text)
            : PasteEnabledTextField(string: text)
        configure(textField, coordinator: context.coordinator)
        textField.identifier = NSUserInterfaceItemIdentifier(rawValue: "PasswordInputTextField")
        textField.setAccessibilityLabel(accessibilityLabel ?? placeholder)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.placeholderString = placeholder
        nsView.setAccessibilityLabel(accessibilityLabel ?? placeholder)
        nsView.menu = makeEditingMenu()
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
}

private final class PasteEnabledTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleClipboardShortcut(event) || super.performKeyEquivalent(with: event)
    }
}

private final class PasteEnabledSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleClipboardShortcut(event) || super.performKeyEquivalent(with: event)
    }
}

private extension NSTextField {
    func handleClipboardShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased()
        else {
            return false
        }

        switch key {
        case "v":
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            return true
        case "c":
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
            return true
        case "x":
            NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
            return true
        case "a":
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
            return true
        default:
            return false
        }
    }
}

final class PasswordFieldCoordinator: NSObject, NSTextFieldDelegate {
    var text: Binding<String>

    init(text: Binding<String>) {
        self.text = text
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }
        text.wrappedValue = textField.stringValue
    }
}

@MainActor
private func configure(_ textField: NSTextField, coordinator: PasswordFieldCoordinator) {
    textField.delegate = coordinator
    textField.isEditable = true
    textField.isSelectable = true
    textField.isBezeled = false
    textField.isBordered = false
    textField.drawsBackground = false
    textField.focusRingType = .none
    textField.font = .systemFont(ofSize: 13)
    textField.lineBreakMode = .byClipping
    textField.placeholderString = ""
    textField.usesSingleLineMode = true
    textField.menu = makeEditingMenu()
    textField.translatesAutoresizingMaskIntoConstraints = false
}

@MainActor
private func makeEditingMenu() -> NSMenu {
    let i18n = LocalizationManager.shared
    let menu = NSMenu()
    menu.addItem(withTitle: i18n.localizedString("menu_cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "")
    menu.addItem(withTitle: i18n.localizedString("menu_copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "")
    menu.addItem(withTitle: i18n.localizedString("menu_paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "")
    menu.addItem(NSMenuItem.separator())
    menu.addItem(withTitle: i18n.localizedString("menu_select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
    return menu
}
