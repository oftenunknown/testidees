import SwiftUI
import Vision
import VisionKit

/// Live camera that recognises barcodes and text together, so a shelf tag
/// with both a barcode and a price is understood in one look.
struct CameraScanner: UIViewControllerRepresentable {
    var isActive: Bool
    var onBarcode: (_ payload: String, _ isUPCE: Bool) -> Void
    var onText: (_ transcript: String) -> Void
    var capture: CaptureTrigger

    /// Lets SwiftUI ask the scanner for a still photo.
    @Observable
    final class CaptureTrigger {
        fileprivate weak var scanner: DataScannerViewController?

        func photo() async -> UIImage? {
            try? await scanner?.capturePhoto()
        }
    }

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean13, .ean8, .upce, .code128, .qr, .itf14, .dataMatrix]),
                .text(),
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        capture.scanner = scanner
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        if isActive, !scanner.isScanning {
            try? scanner.startScanning()
        } else if !isActive, scanner.isScanning {
            scanner.stopScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: CameraScanner

        init(parent: CameraScanner) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(updatedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            for item in items {
                switch item {
                case .barcode(let barcode):
                    if let payload = barcode.payloadStringValue {
                        parent.onBarcode(payload, barcode.observation.symbology == .upce)
                    }
                case .text(let text):
                    parent.onText(text.transcript)
                @unknown default:
                    break
                }
            }
        }
    }
}
