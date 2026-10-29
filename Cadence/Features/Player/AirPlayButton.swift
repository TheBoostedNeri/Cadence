// iPhone and iPad only: the Mac picks speakers from the menu bar.
#if os(iOS)
import AVKit
import SwiftUI

/// The system's AirPlay button, for choosing speakers and TVs, as in Apple Music's Now Playing.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor(Palette.textSecondary)
        picker.activeTintColor = UIColor(Palette.brand)
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}
#endif
