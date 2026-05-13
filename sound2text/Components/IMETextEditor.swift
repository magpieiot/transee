//
//  TextView.swift
//  sound2text
//
//  Created by gavanwang on 12/2/25.
//


import SwiftUI
import AppKit

struct IMETextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var calculatedHeight: CGFloat // 用于将计算出的高度传递回 SwiftUI
    var rowSN: Int
    var isEditable: Bool = true
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var measureWidth: CGFloat? = nil
    var onEdited: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = font
        textView.isRichText = false
        textView.importsGraphics = false
        if let container = textView.textContainer {
            container.widthTracksTextView = false
            let w = measureWidth ?? (textView.bounds.width > 0 ? textView.bounds.width : 400)
            container.containerSize = NSSize(width: w, height: .greatestFiniteMagnitude)
        }
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.string = text
        context.coordinator.textView = textView
        Task { @MainActor in
            context.coordinator.scheduleHeightUpdate()
        }
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable
        textView.font = font
        if let container = textView.textContainer {
            let width = max(10, measureWidth ?? textView.bounds.width)
            container.widthTracksTextView = false
            if abs(container.containerSize.width - width) > 1 {
                container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            }
        }
        context.coordinator.scheduleHeightUpdate()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IMETextEditor
        var textView: NSTextView?
        var isHeightUpdateScheduled = false

        init(_ parent: IMETextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onEdited?()
            scheduleHeightUpdate()
        }

        func scheduleHeightUpdate() {
            if isHeightUpdateScheduled { return }
            isHeightUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isHeightUpdateScheduled = false
                self.updateHeight()
            }
        }
        
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            // This delegate method is important for IME.
            // Returning true allows the change, false rejects it.
            // By default, we allow changes.
            return true
        }
        
        func updateHeight() {
            guard let textView = textView, let container = textView.textContainer else { return }
            textView.layoutManager?.ensureLayout(for: container)
            let layoutRect = textView.layoutManager?.usedRect(for: container) ?? .zero
            let minHeight: CGFloat = 16.0
            let newHeight = max(minHeight, layoutRect.height + textView.textContainerInset.height * 2)
            if abs(newHeight - parent.calculatedHeight) > 2 {
                parent.calculatedHeight = newHeight
            }
        }
    }
}
