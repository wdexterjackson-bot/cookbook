//
//  SamplePDFPreviewView.swift
//  cookbook
//
//  Shows the bundled Sample.pdf (Administrator screen's "View Sample
//  Import File" row) — a real recipe file in exactly the format both
//  Import Recipes from File and Export Cookbook to PDF use, so someone
//  can see what a properly formatted import document looks like before
//  building their own. Not available on tvOS — PDFKit's PDFView has no
//  tvOS-friendly remote-navigable form, and there's no file system to
//  view documents from on that platform anyway.
//

import SwiftUI
#if !os(tvOS)
import PDFKit

struct SamplePDFPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let url = Bundle.main.url(forResource: "Sample", withExtension: "pdf") {
                    PDFKitRepresentedView(url: url)
                } else {
                    ContentUnavailableView("Sample Not Found", systemImage: "doc.questionmark")
                }
            }
            .navigationTitle("Sample Import File")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#if os(macOS)
private struct PDFKitRepresentedView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {}
}
#else
private struct PDFKitRepresentedView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
#endif

#Preview {
    SamplePDFPreviewView()
}
#endif
