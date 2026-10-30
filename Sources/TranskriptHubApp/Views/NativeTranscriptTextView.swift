import SwiftUI
import AppKit

public struct NativeTranscriptTextView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let searchHighlight: String
    let autoScrollToEnd: Bool
    
    public init(text: String, fontSize: CGFloat = 13, searchHighlight: String = "", autoScrollToEnd: Bool = false) {
        self.text = text
        self.fontSize = fontSize
        self.searchHighlight = searchHighlight
        self.autoScrollToEnd = autoScrollToEnd
    }
    
    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        
        let contentSize = scrollView.contentSize
        let textView = FocusableTranscriptTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0.0, height: 0.0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = NSColor.labelColor
        
        if let container = textView.textContainer {
            container.containerSize = NSSize(width: max(100, contentSize.width), height: CGFloat.greatestFiniteMagnitude)
            container.widthTracksTextView = true
            container.lineFragmentPadding = 0
        }
        textView.textContainerInset = NSSize(width: 30, height: 24)
        
        scrollView.documentView = textView
        updateTextView(textView)
        return scrollView
    }
    
    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.frame.width != scrollView.contentSize.width && scrollView.contentSize.width > 0 {
            textView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: max(scrollView.contentSize.height, textView.frame.height))
        }
        updateTextView(textView)
    }
    
    private func updateTextView(_ textView: NSTextView) {
        // Sanitize redundant consecutive newlines (collapse 3+ newlines into 2)
        var cleanText = text.replacingOccurrences(of: "\r\n", with: "\n")
        while cleanText.contains("\n\n\n") {
            cleanText = cleanText.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        
        let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = max(4.5, round(fontSize * 0.40))
        // Since paragraphs are already separated by empty lines (\n\n), paragraphSpacing is set to 0 to prevent giant white gaps
        paragraphStyle.paragraphSpacing = 0
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributed = NSMutableAttributedString(string: cleanText, attributes: attributes)
        
        // Highlight search query if provided
        if !searchHighlight.isEmpty {
            let nsText = cleanText as NSString
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
        
        if textView.string != cleanText || textView.font?.pointSize != fontSize {
            let currentSelection = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributed)
            if currentSelection.location + currentSelection.length <= cleanText.count {
                textView.setSelectedRange(currentSelection)
            }
        }
        
        if autoScrollToEnd {
            textView.scrollToEndOfDocument(nil)
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
