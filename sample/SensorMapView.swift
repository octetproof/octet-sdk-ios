import SwiftUI
import MapKit

/// The device's own location on a map — real pin + the system accuracy ring
/// (MapKit's `UserAnnotation`). Cell towers and satellites can't be plotted on
/// iOS (their positions aren't exposed), so this shows only the device; those
/// overlays are the Android build's job.
struct SensorMapView: View {
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $camera) {
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            Text("Only the device is shown here. iOS exposes no per-satellite data, so satellites can't be drawn — the Android build renders them as a sky view. Cell towers can't be mapped on either platform (their positions aren't public); Android shows their signal strength instead.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.m)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
    }
}
