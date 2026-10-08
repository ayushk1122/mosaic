import PhotosUI
import SwiftUI

struct BlockInspectorSheet: View {
    let documentID: ComposerDocumentID?
    @Binding var block: ComposerBlock
    @Environment(ComposerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                if block.kind == .text || block.kind == .heading {
                    textStyleSection
                }

                switch block.kind {
                case .text, .heading:
                    Section("Copy") {
                        TextField("Text", text: $block.text, axis: .vertical)
                            .lineLimit(3 ... 8)
                    }
                case .link:
                    Section("Link") {
                        TextField("Title", text: $block.text)
                        TextField("URL", text: Binding(
                            get: { block.linkURL ?? "" },
                            set: { block.linkURL = $0 }
                        ))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    }
                case .pursuit:
                    Section("Pursuit") {
                        TextField("Name", text: $block.text)
                    }
                case .calendar:
                    Section("Calendar") {
                        Text("Open a day on the calendar to add a carousel of photos and videos, or a note.")
                            .foregroundStyle(.secondary)
                    }
                case .list:
                    Section("List") {
                        Text("Starts as bullets. The style menu switches to numbers, checkboxes, dashes, or letters.")
                            .foregroundStyle(.secondary)
                    }
                case .graph:
                    Section("Graph") {
                        Text("A line graph. Add dated points and the line connects them.")
                            .foregroundStyle(.secondary)
                    }
                case .carousel:
                    Section("Carousel") {
                        Text("Add, replace, or remove items from the carousel on the page.")
                            .foregroundStyle(.secondary)
                    }
                case .media:
                    Section("Photo") {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Replace photo", systemImage: "photo.on.rectangle")
                        }
                    }
                }

                Section("Arrangement") {
                    Button("Move up") {
                        store.moveBlock(block.id, direction: .up, in: documentID)
                        dismiss()
                    }
                    Button("Move down") {
                        store.moveBlock(block.id, direction: .down, in: documentID)
                        dismiss()
                    }
                    Button("Delete", role: .destructive) {
                        store.deleteBlock(block.id, in: documentID)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.updateBlock(block, in: documentID)
                        dismiss()
                    }
                }
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let fileName = try? store.saveMediaData(data) {
                        block.mediaFileName = fileName
                        store.setMedia(fileName, for: block.id, in: documentID)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var textStyleSection: some View {
        Section("Style") {
            Picker("Size", selection: $block.style.size) {
                ForEach(TextBlockSize.allCases, id: \.self) { size in
                    Text(size.label).tag(size)
                }
            }
            Picker("Color", selection: $block.style.color) {
                ForEach(TextBlockColor.allCases, id: \.self) { color in
                    Text(color.label).tag(color)
                }
            }
            Picker("Alignment", selection: $block.style.alignment) {
                ForEach(TextAlignmentOption.allCases, id: \.self) { alignment in
                    Text(alignment.label).tag(alignment)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
