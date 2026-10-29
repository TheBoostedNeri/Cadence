// iPhone and iPad only: macOS has no MPVolumeView, and Mac volume lives in the menu bar and keyboard.
#if os(iOS)
import MediaPlayer
import SwiftUI

/// The device volume, like Apple Music: the hardware buttons move it and dragging it changes the
/// system volume. Apple only exposes system volume through `MPVolumeView`, so the slider itself
/// is UIKit. It has nothing to control in the Simulator, so it only works on a real device.
struct SystemVolumeSlider: View {
    var body: some View {
        HStack(spacing: Spacing.medium) {
            Image(systemName: "speaker.fill")
                .accessibilityHidden(true)
            VolumeView()
                .frame(height: TouchTarget.minimum)
            Image(systemName: "speaker.wave.3.fill")
                .accessibilityHidden(true)
        }
        .font(Typography.caption)
        .foregroundStyle(Palette.textSecondary)
    }
}

private struct VolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> CenteredVolumeView {
        let volumeView = CenteredVolumeView(frame: .zero)
        // White on Now Playing's dark background, like Apple Music.
        volumeView.tintColor = UIColor(Palette.textPrimary)
        return volumeView
    }

    func updateUIView(_ volumeView: CenteredVolumeView, context: Context) {}
}

/// `MPVolumeView` draws its slider at the top of its frame; this keeps it vertically centered,
/// in line with the speaker icons, while the frame stays a full tap target tall.
private final class CenteredVolumeView: MPVolumeView {
    override func volumeSliderRect(forBounds bounds: CGRect) -> CGRect {
        var rect = super.volumeSliderRect(forBounds: bounds)
        rect.origin.y = bounds.midY - rect.height / 2
        return rect
    }
}
#endif
