import AVFoundation
import MapKit
import SwiftUI

struct RouteARNavigationView: View {
    let option: HomeRouteOption
    let onClose: () -> Void

    @StateObject private var locationManager = HomeLocationManager()

    private var routeBearing: Double {
        option.primaryBearing(from: locationManager.displayCoordinate) ?? locationManager.heading
    }

    private var relativeTurnAngle: Double {
        let delta = routeBearing - locationManager.heading
        return ((delta + 540).truncatingRemainder(dividingBy: 360)) - 180
    }

    private var currentInstruction: RouteARInstruction {
        option.arInstruction(from: locationManager.displayCoordinate)
    }

    var body: some View {
        ZStack {
            CameraPreviewView()
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.16),
                    Color.clear,
                    Color.black.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            closeButtonLayer

            ARRouteChevronOverlay()
                .rotationEffect(.degrees(relativeTurnAngle * 0.18))
                .allowsHitTesting(false)

            VStack {
                Spacer()

                ARInstructionOverlay(
                    instruction: currentInstruction,
                    relativeTurnAngle: relativeTurnAngle
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 220)
            }

            VStack {
                Spacer()

                ARMiniMapCard(
                    option: option,
                    userCoordinate: locationManager.displayCoordinate,
                    heading: locationManager.heading
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 22)
            }
        }
        .onAppear { locationManager.start() }
    }

    private var closeButtonLayer: some View {
        VStack {
            HStack {
                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DS.Color.ink)
                        .frame(width: 38, height: 38)
                        .background(DS.Color.paper.opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 62)

            Spacer()
        }
    }
}

private struct ARRouteChevronOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Path { path in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    let centerX = width * 0.52
                    path.addArc(
                        center: CGPoint(x: centerX, y: height * 0.72),
                        radius: width * 0.28,
                        startAngle: .degrees(198),
                        endAngle: .degrees(330),
                        clockwise: false
                    )
                }
                .stroke(
                    AppTheme.Palette.info.opacity(0.55),
                    style: StrokeStyle(lineWidth: 22, lineCap: .round)
                )
                .blur(radius: 4)

                VStack(spacing: 10) {
                    Spacer()

                    ForEach(0..<8, id: \.self) { index in
                        ARChevronShape()
                            .fill(AppTheme.Palette.info.opacity(0.92 - Double(index) * 0.08))
                            .frame(
                                width: max(54, 148 - CGFloat(index) * 12),
                                height: max(24, 56 - CGFloat(index) * 4)
                            )
                            .shadow(color: AppTheme.Palette.info.opacity(0.45), radius: 10, x: 0, y: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 132)
            }
        }
    }
}

private struct ARMiniMapCard: View {
    let option: HomeRouteOption
    let userCoordinate: CLLocationCoordinate2D
    let heading: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(option.destinationName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                Text(option.durationText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Color.paper.opacity(0.96))

                Map(initialPosition: .rect(option.mapRectWithPadding)) {
                    if option.routeCoordinates.count > 1 {
                        MapPolyline(coordinates: option.routeCoordinates)
                            .stroke(DS.Color.community, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    }

                    Annotation("", coordinate: userCoordinate, anchor: .center) {
                        ZStack {
                            Circle()
                                .fill(DS.Color.community.opacity(0.16))
                                .frame(width: 52, height: 52)
                            Circle()
                                .fill(DS.Color.primary)
                                .frame(width: 26, height: 26)
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(heading))
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .environment(\.colorScheme, .light)
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .frame(height: 170)
        }
        .padding(18)
        .background(DS.Color.paper.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct ARChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.34))
        path.addLine(to: CGPoint(x: rect.width * 0.28, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private struct ARInstructionOverlay: View {
    let instruction: RouteARInstruction
    let relativeTurnAngle: Double

    private var directionText: String {
        switch relativeTurnAngle {
        case ..<(-35): return "Tournez à gauche"
        case 35...: return "Tournez à droite"
        default: return "Continuez tout droit"
        }
    }

    private var directionIcon: String {
        switch relativeTurnAngle {
        case ..<(-35): return "arrow.turn.up.left"
        case 35...: return "arrow.turn.up.right"
        default: return "arrow.up"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: directionIcon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Color.community)

                Text(directionText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.ink)

                Spacer()

                Text(instruction.distanceText)
                    .font(DS.Font.monoSmall.weight(.bold))
                    .foregroundStyle(DS.Color.ink)
            }

            Text(instruction.primaryText)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let secondaryText = instruction.secondaryText {
                Text(secondaryText)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(DS.Color.paper.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    func makeUIView(context: Context) -> CameraPreviewUIView {
        CameraPreviewUIView()
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

private final class CameraPreviewUIView: UIView {
    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        configureSession()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    private func configureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupInputAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.setupInputAndStart()
                    }
                }
            }
        default:
            break
        }
    }

    private func setupInputAndStart() {
        guard session.inputs.isEmpty,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high
        session.addInput(input)
        session.commitConfiguration()
        previewLayer.session = session

        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
    }

    deinit {
        if session.isRunning {
            session.stopRunning()
        }
    }
}
