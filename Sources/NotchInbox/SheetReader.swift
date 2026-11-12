import AppKit
import PDFKit
import Vision

/// Gets the words out of a task sheet: a PDF, a Word or text file, or a photo or
/// screenshot of one. Everything here happens on this Mac; photos and scanned PDFs are
/// read with macOS's own text recognition.
enum SheetReader {
    /// The file's words, tidied, or "" if none could be found. Reading a long scan takes a
    /// few seconds, so call this off the main thread.
    static func text(of url: URL) -> String {
        let kind = AssignmentSheet.kind(of: url.lastPathComponent)
        var text = ""
        if kind == "pdf" {
            text = pdf(url)
        } else if AssignmentSheet.images.contains(kind) {
            text = picture(url)
        } else if kind == "html" || kind == "htm" {
            text = EmailContent.text(fromHTML: plain(url))
        } else if ["txt", "text", "md", "markdown"].contains(kind) {
            text = plain(url)
        } else {
            // Word, RTF and OpenDocument files: macOS can open these itself.
            text = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string ?? ""
        }
        return AssignmentSheet.tidy(text)
    }

    private static func plain(_ url: URL) -> String {
        var encoding = String.Encoding.utf8
        return (try? String(contentsOf: url, usedEncoding: &encoding)) ?? ""
    }

    /// A PDF's own words; or, if it's a scan with none, its first pages read as pictures.
    private static func pdf(_ url: URL) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        let written = document.string ?? ""
        if written.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 {
            return written
        }
        var pages: [String] = []
        for index in 0..<min(document.pageCount, 6) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let size = CGSize(width: max(1, bounds.width * 2), height: max(1, bounds.height * 2))
            let image = page.thumbnail(of: size, for: .mediaBox)
            if let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                pages.append(recognise(picture))
            }
        }
        return pages.joined(separator: "\n")
    }

    private static func picture(_ url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return "" }
        return recognise(image)
    }

    /// The words macOS can see in a picture, a line at a time.
    private static func recognise(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
