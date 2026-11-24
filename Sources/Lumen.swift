import PDFKit
import SwiftUI

@main
struct Lumen: App {
    @StateObject private var reader = Reader()
    var body: some Scene {
        Window("Lumen", id: "reader") {
            ReaderWindow(reader: reader)
                .frame(minWidth: 680, minHeight: 480)
                .alert("Lumen", isPresented: Binding(get: { reader.error != nil }, set: { if !$0 { reader.error = nil } })) {
                    Button("OK") { reader.error = nil }
                } message: { Text(reader.error ?? "") }
        }
        .defaultSize(width: 980, height: 740)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open PDF…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.pdf]
                    if panel.runModal() == .OK, let url = panel.url { reader.open(url) }
                }.keyboardShortcut("o")
            }
        }
    }
}

struct ReaderWindow: View {
    @ObservedObject var reader: Reader
    @State private var showingShelf = false
    @State private var showingBookmarks = false

    var body: some View {
        Group {
            if let book = reader.book {
                VStack(spacing: 0) {
                    PageView(reader: reader)
                    Divider()
                    HStack {
                        Text(book.url.deletingPathExtension().lastPathComponent).lineLimit(1)
                        Spacer()
                        Button { reader.jump(reader.state.page - 1) } label: { Image(systemName: "chevron.left") }
                            .disabled(reader.state.page == 0).help("Previous page")
                        Text("Page \(reader.state.page + 1) of \(book.document.pageCount)").monospacedDigit()
                        Button { reader.jump(reader.state.page + 1) } label: { Image(systemName: "chevron.right") }
                            .disabled(reader.state.page + 1 >= book.document.pageCount).help("Next page")
                    }
                    .font(.callout).padding(.horizontal, 16).padding(.vertical, 8)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "books.vertical").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("Reading room").font(.system(size: 42, weight: .regular, design: .serif))
                    if let url = reader.lastURL {
                        Text(url.deletingPathExtension().lastPathComponent).font(.title3).lineLimit(2)
                        Button("Continue reading") { reader.open(url) }.controlSize(.large)
                    } else {
                        Text("Choose a book from your PDF folder.").foregroundStyle(.secondary)
                        Button("Browse books") { showingShelf = true }.controlSize(.large)
                    }
                }.padding(48).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { showingShelf.toggle() } label: { Label("Books", systemImage: "books.vertical") }
                    .help("Browse your PDF folder").keyboardShortcut("l")
                    .popover(isPresented: $showingShelf, arrowEdge: .bottom) { Shelf(reader: reader) }
            }
            if reader.book != nil {
                ToolbarItem {
                    Picker("Reading tool", selection: $reader.tool) {
                        ForEach(ReadingTool.allCases, id: \.self) { tool in
                            Image(systemName: tool.symbol).accessibilityLabel(tool.rawValue).help(tool.rawValue).tag(tool)
                        }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                ToolbarItem {
                    Button { reader.toggleBookmark() } label: {
                        let set = reader.state.bookmarks.contains(reader.state.page)
                        Label(set ? "Remove bookmark" : "Bookmark page", systemImage: set ? "bookmark.fill" : "bookmark")
                    }.keyboardShortcut("d").help("Toggle bookmark for this page")
                }
                ToolbarItem {
                    Button { showingBookmarks.toggle() } label: { Label("Bookmarks", systemImage: "list.bullet") }
                        .help("Show bookmarks").popover(isPresented: $showingBookmarks) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Bookmarks").font(.headline)
                                if reader.state.bookmarks.isEmpty { Text("Use the bookmark button to mark a page.").foregroundStyle(.secondary) }
                                else {
                                    ScrollView {
                                        LazyVStack(alignment: .leading, spacing: 8) {
                                            ForEach(reader.state.bookmarks, id: \.self) { index in
                                                Button("Page \(index + 1)") { reader.jump(index); showingBookmarks = false }
                                            }
                                        }
                                    }.frame(maxHeight: 250)
                                }
                            }.padding(16).frame(width: 230, alignment: .leading)
                        }
                }
            }
        }
    }
}
