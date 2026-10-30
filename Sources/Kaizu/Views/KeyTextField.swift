import AppKit
import SwiftUI

/// Single-line text field that reports ↑/↓, ↩ and ⎋ before the field editor
/// handles them, and takes focus (selecting its text) when it appears.
/// With `complete`, typing at the end fills in the rest, selected, so the
/// next keystroke or ⌫ replaces it (Safari's inline completion).
/// Used by the command bar and the find bar.
struct KeyTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var fontSize: CGFloat = 19
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void
    var complete: ((String) -> String?)?

    func makeNSView(context: Context) -> FocusingTextField {
        let field = FocusingTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        let font = NSFont.systemFont(ofSize: fontSize)
        field.font = font
        field.textColor = .labelColor
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        )
        field.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.stringValue = text
        field.delegate = context.coordinator
        context.coordinator.typedText = text
        return field
    }

    func updateNSView(_ field: FocusingTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: KeyTextField
        /// What the user typed, without any filled-in completion. Completion
        /// only follows text that grew, so ⌫, cut and undo never refill it.
        var typedText = ""
        private var isCompleting = false

        init(parent: KeyTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isCompleting, let field = notification.object as? NSTextField else { return }
            let typed = field.stringValue
            let grew = typed.count > typedText.count
            typedText = typed
            let length = (typed as NSString).length
            guard grew, let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText(),
                  editor.selectedRange == NSRange(location: length, length: 0),
                  let completion = parent.complete?(typed)
            else { return parent.text = typed }
            // Inserted as an ordinary (undoable) edit, then selected so the
            // next keystroke replaces it.
            let suffix = String(completion.dropFirst(typed.count))
            let end = NSRange(location: length, length: 0)
            isCompleting = true
            if editor.shouldChangeText(in: end, replacementString: suffix) {
                editor.replaceCharacters(in: end, with: suffix)
                editor.didChangeText()
            }
            isCompleting = false
            editor.selectedRange = NSRange(location: length, length: (suffix as NSString).length)
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
            default:
                return false
            }
            return true
        }
    }
}

final class FocusingTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        Task { [weak self] in
            guard let self else { return }
            window.makeFirstResponder(self)
            self.currentEditor()?.selectAll(nil)
        }
    }
}
