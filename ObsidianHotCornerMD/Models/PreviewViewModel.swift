import Foundation

class PreviewViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var fileURL: URL?
    @Published var quickNoteText: String = ""
    @Published var quickNoteError: String?
}
