import SwiftUI
import AppKit

public struct NativeTranscriptTextView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let searchHighlight: String
    
    public init(text: String, fontSize: CGFloat = 13, searchHighlight: String = "") {
        self.text = text
        self.fontSize = fontSize
        self.searchHighlight = searchHighlight
    }
    
    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        
        let textView = FocusableTranscriptTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 24, height: 24)
        
        scrollView.documentView = textView
        updateTextView(textView)
        return scrollView
    }
    
    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        updateTextView(textView)
    }
    
    private func updateTextView(_ textView: NSTextView) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        paragraphStyle.paragraphSpacing = 14
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributed = NSMutableAttributedString(string: text, attributes: attributes)
        
        // Highlight search query if provided
        if !searchHighlight.isEmpty {
            let nsText = text as NSString
            var range = nsText.range(of: searchHighlight, options: .caseInsensitive)
            while range.location != NSNotFound {
                attributed.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: range)
                let nextLoc = range.location + range.length
                if nextLoc < nsText.length {
                    range = nsText.range(of: searchHighlight, options: .caseInsensitive, range: NSRange(location: nextLoc, length: nsText.length - nextLoc))
                } else {
                    break
                }
            }
        }
        
        if textView.attributedString().string != text || textView.font?.pointSize != fontSize {
            let currentSelection = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributed)
            if currentSelection.location + currentSelection.length <= text.count {
                textView.setSelectedRange(currentSelection)
            }
        }
    }
}

private final class FocusableTranscriptTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        
        // Handle Command+A (Select All)
        if flags == .command && chars == "a" {
            self.selectAll(nil)
            return true
        }
        
        // Handle Command+C (Copy)
        if flags == .command && chars == "c" {
            self.copy(nil)
            return true
        }
        
        return super.performKeyEquivalent(with: event)
    }
}
