import SwiftUI
import PDFKit

private actor Covers {
    static let shared = Covers()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 96 }

    func cover(_ url: URL) -> NSImage? {
        guard !Task.isCancelled, let version = try? FileVersion(url) else { return nil }
        let key = "\(url.path):\(version.inode):\(version.modified.timeIntervalSince1970)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        let image = page.thumbnail(of: NSSize(width: 180, height: 240), for: .cropBox)
        cache.setObject(image, forKey: key)
        return image
    }
}

struct Cover: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "doc").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .frame(width: 80, height: 104)
        .task(id: url) {
            let result = await Covers.shared.cover(url)
            if !Task.isCancelled { image = result }
        }
    }
}

struct Shelf: View {
    @ObservedObject var reader: Reader
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Books").font(.title2.weight(.semibold))
                Spacer()
                Button(reader.folder == nil ? "Choose folder…" : "Change folder…") { reader.chooseFolder() }
            }
            if let folder = reader.folder {
                Text(folder.path(percentEncoded: false)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Divider()
            if reader.books.isEmpty {
                Spacer()
                if reader.scanning || reader.preparingLibrary {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let folder = reader.folder {
                    VStack(spacing: 10) {
                        Text("Add a PDF to this folder to see its cover here.")
                            .foregroundStyle(.secondary)
                        Button("Open folder in Finder") {
                            if !NSWorkspace.shared.open(folder) { reader.error = "Could not open the PDF folder in Finder." }
                        }
                    }.frame(maxWidth: .infinity)
                } else if let error = reader.librarySetupError {
                    VStack(spacing: 10) {
                        Text("Couldn’t open Lumen Library in Documents.")
                        Text(error).font(.callout).foregroundStyle(.secondary)
                        Button("Retry library setup") { reader.prepareLibrary(retry: true) }
                        Button("Open PDF…") { dismiss(); reader.choosePDF() }
                    }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
                } else {
                    Text("Choose the folder where you keep your PDFs.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                Spacer()
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(reader.books, id: \.self) { url in
                            Button {
                                dismiss()
                                reader.open(url)
                            } label: {
                                HStack(spacing: 18) {
                                    Cover(url: url)
                                    Text(url.deletingPathExtension().lastPathComponent)
                                        .font(.system(size: 16, weight: .medium, design: .serif)).lineLimit(3)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 10).padding(.horizontal, 4)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(18).frame(width: 384, height: 460)
        .onChange(of: reader.folder, initial: true) {
            reader.watchFolder()
            reader.refresh()
        }
    }
}
