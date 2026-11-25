import PDFKit
import SwiftUI

@main
struct Lumen: App {
    @StateObject private var reader = Reader()
    var body: some Scene {
        Window("Lumen", id: "reader") {
            ReaderWindow(reader: reader)
                .frame(minWidth: 680, minHeight: 480)
                .onAppear { reader.prepareLibrary() }
                .alert("Lumen", isPresented: Binding(get: { reader.error != nil }, set: { if !$0 { reader.error = nil } })) {
                    Button("OK") { reader.error = nil }
                } message: { Text(reader.error ?? "") }
        }
        .defaultSize(width: 980, height: 740)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open PDF…") { reader.choosePDF() }.keyboardShortcut("o")
            }
            CommandGroup(after: .toolbar) {
                Group {
                    Button("Zoom In") { reader.pdfView?.zoomIn(nil) }.keyboardShortcut("+")
                    Button("Zoom Out") { reader.pdfView?.zoomOut(nil) }.keyboardShortcut("-")
                    Button("Fit Page") { reader.pdfView?.autoScales = true }.keyboardShortcut("0")
                }.disabled(reader.book == nil)
            }
        }
    }
}
