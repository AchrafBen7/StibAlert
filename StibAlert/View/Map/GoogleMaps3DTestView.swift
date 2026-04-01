import SwiftUI
import GoogleMaps3D

struct GoogleMaps3DTestView: View {
    @Environment(\.dismiss) private var dismiss

    init() {
        Map.apiKey = AppConfig.googleMaps3DAPIKey
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(
                initialCamera: .init(
                    center: .init(
                        latitude: 50.84673,
                        longitude: 4.35247,
                        altitude: 280
                    ),
                    heading: 18,
                    tilt: 62,
                    range: 1400
                ),
                mode: .hybrid
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.primaryText)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Google Maps 3D test")
                        .font(DesignSystem.Typography.sectionTitleSmall)
                        .foregroundStyle(.white)

                    Text("Brussels center in hybrid 3D, loaded with the Maps 3D SDK for iOS.")
                        .font(DesignSystem.Typography.description)
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.top, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
