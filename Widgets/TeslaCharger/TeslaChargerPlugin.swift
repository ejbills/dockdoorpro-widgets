import DockDoorWidgetSDK
import Foundation
import SwiftUI

final class TeslaChargerPlugin: WidgetPlugin, DockDoorWidgetProvider {
    var id: String { "tesla-charger" }
    var name: String { "Tesla Charger" }
    var iconSymbol: String { "bolt.car.fill" }
    var widgetDescription: String { "Tesla charging status and Fleet API controls" }
    var supportedOrientations: [WidgetOrientation] { [.horizontal, .vertical] }

    private let model = TeslaChargerModel(widgetId: "tesla-charger")

    func settingsSchema() -> [WidgetSetting] {
        [
            .textField(
                key: "apiBaseURL",
                label: "Fleet API Base URL",
                placeholder: "https://fleet-api.prd.na.vn.cloud.tesla.com",
                defaultValue: TeslaChargerConfig.defaultBaseURL
            ),
            .textField(
                key: "accessToken",
                label: "Tesla OAuth Access Token",
                placeholder: "Bearer token with vehicle data and command scopes",
                defaultValue: ""
            ),
            .textField(
                key: "refreshToken",
                label: "Tesla OAuth Refresh Token",
                placeholder: "Refresh token from Tesla OAuth login",
                defaultValue: ""
            ),
            .textField(
                key: "clientId",
                label: "Tesla OAuth Client ID",
                placeholder: "Tesla developer app client ID",
                defaultValue: ""
            ),
            .textField(
                key: "vehicleVin",
                label: "Vehicle VIN",
                placeholder: "5YJ...",
                defaultValue: ""
            ),
            .textField(
                key: "skinImageURL",
                label: "Skin Image URL",
                placeholder: "https://.../model3-skin.png",
                defaultValue: ""
            ),
            .textField(
                key: "skinImagePath",
                label: "Local Skin Image Path",
                placeholder: "~/Pictures/tesla-model-3-skin.png",
                defaultValue: ""
            ),
            .slider(
                key: "refreshInterval",
                label: "Refresh Interval Seconds",
                range: 30...600,
                step: 30,
                defaultValue: 120
            ),
            .toggle(
                key: "wakeForRefresh",
                label: "Wake Vehicle Before Refresh",
                defaultValue: false
            ),
        ]
    }

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(TeslaChargerCompactView(size: size, isVertical: isVertical, model: model))
    }

    @MainActor
    func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
        AnyView(TeslaChargerPanelView(dismiss: dismiss, model: model))
    }
}

private struct TeslaChargerCompactView: View {
    let size: CGSize
    let isVertical: Bool
    @ObservedObject var model: TeslaChargerModel

    private var dim: CGFloat { min(size.width, size.height) }
    private var isExtended: Bool {
        isVertical ? size.height > size.width * 1.5 : size.width > size.height * 1.5
    }

    var body: some View {
        Group {
            if isExtended {
                extendedLayout
            } else {
                compactLayout
            }
        }
        .task {
            await model.runRefreshLoop()
        }
    }

    private var compactLayout: some View {
        Group {
            if model.hasSkinImage {
                ZStack(alignment: .bottomTrailing) {
                    vehicleArtwork
                        .frame(width: size.width * 0.9, height: size.height * 0.82)

                    Text(model.snapshot.batteryLabel)
                        .font(.system(size: max(10, dim * 0.18), weight: .bold, design: .rounded))
                        .foregroundStyle(model.snapshot.tint)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.thinMaterial, in: Capsule())
                }
                .padding(dim * 0.05)
            } else {
                VStack(spacing: dim * 0.06) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.16), lineWidth: max(3, dim * 0.06))
                        Circle()
                            .trim(from: 0, to: model.snapshot.batteryFraction)
                            .stroke(model.snapshot.tint, style: StrokeStyle(lineWidth: max(3, dim * 0.06), lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: model.snapshot.icon)
                            .font(.system(size: dim * 0.28, weight: .semibold))
                            .foregroundStyle(model.snapshot.tint)
                    }
                    .frame(width: dim * 0.62, height: dim * 0.62)

                    Text(model.snapshot.batteryLabel)
                        .font(.system(size: dim * 0.2, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(dim * 0.1)
            }
        }
    }

    private var extendedLayout: some View {
        Group {
            if isVertical {
                VStack(spacing: dim * 0.08) {
                    vehicleArtwork
                        .frame(width: size.width * 0.92, height: size.height * 0.56)
                    statusLabels(alignment: .center)
                }
            } else {
                HStack {
                    Spacer(minLength: 0)
                    vehicleArtwork
                        .frame(width: size.width * 0.78, height: size.height * 0.9)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, max(4, dim * 0.06))
            }
        }
    }

    private func statusLabels(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(model.snapshot.modelDisplayName)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(model.snapshot.statusLine)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    @ViewBuilder
    private var vehicleArtwork: some View {
        if let url = model.skinImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    fallbackVehicleArtwork
                case .empty:
                    ProgressView()
                        .controlSize(.small)
                @unknown default:
                    fallbackVehicleArtwork
                }
            }
        } else if let image = model.localSkinImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            fallbackVehicleArtwork
        }
    }

    private var fallbackVehicleArtwork: some View {
        Image(systemName: "car.side.fill")
            .font(.system(size: dim * 0.48, weight: .semibold))
            .foregroundStyle(model.snapshot.tint)
    }
}

private struct TeslaChargerPanelView: View {
    let dismiss: () -> Void
    @ObservedObject var model: TeslaChargerModel
    @State private var chargeLimit = 80.0
    @State private var chargingAmps = 32.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.hasSkinImage {
                vehicleArtworkPreview
            }

            vehicleIdentity

            HStack(spacing: 10) {
                TeslaMetricTile(title: "Battery", value: model.snapshot.batteryLabel, tint: model.snapshot.tint)
                TeslaMetricTile(title: "Limit", value: model.snapshot.limitLabel, tint: .blue)
                TeslaMetricTile(title: "Power", value: model.snapshot.powerLabel, tint: .orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                panelRow("Vehicle", model.snapshot.vehicleName, "car.fill")
                panelRow("State", model.snapshot.statusLine, model.snapshot.icon)
                panelRow("Skin", model.skinStatusLabel, "paintpalette.fill")
                panelRow("Current", model.snapshot.currentLabel, "alternatingcurrent")
                panelRow("Added", model.snapshot.energyAddedLabel, "plus.circle.fill")
                panelRow("Odometer", model.snapshot.odometerLabel, "road.lanes")
                panelRow("Software", model.snapshot.softwareLabel, "cpu")
                panelRow("FSD", model.snapshot.fsdLabel, "steeringwheel")
                panelRow("Release", model.snapshot.releaseNoteLabel, "doc.text.fill")
                panelRow("Updated", model.snapshot.updatedLabel, "clock")
            }

            if let message = model.message {
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(model.hasError ? .red : .secondary)
                    .lineLimit(2)
            }

            Divider()

            HStack(spacing: 8) {
                commandButton("Start", "bolt.fill") {
                    await model.sendCommand(.startCharging)
                }
                commandButton("Stop", "stop.fill") {
                    await model.sendCommand(.stopCharging)
                }
                commandButton("Port", "bolt.badge.automatic") {
                    await model.sendCommand(.openChargePort)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Limit", systemImage: "battery.75percent")
                    Spacer()
                    Text("\(Int(chargeLimit))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                Slider(value: $chargeLimit, in: 50...100, step: 5)
                Button {
                    Task { await model.sendCommand(.setChargeLimit(Int(chargeLimit))) }
                } label: {
                    Label("Set Charge Limit", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Amps", systemImage: "gauge.with.dots.needle.67percent")
                    Spacer()
                    Text("\(Int(chargingAmps)) A")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                Slider(value: $chargingAmps, in: 5...48, step: 1)
                Button {
                    Task { await model.sendCommand(.setChargingAmps(Int(chargingAmps))) }
                } label: {
                    Label("Set Charging Amps", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Text("Command support depends on Tesla token scopes, virtual key setup, and whether the vehicle requires signed commands.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(3)
        }
        .padding(14)
        .frame(width: 340)
        .task {
            chargeLimit = Double(model.snapshot.chargeLimit ?? 80)
            chargingAmps = Double(max(5, model.snapshot.chargingAmps ?? 32))
            await model.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Tesla Charger", systemImage: "bolt.car.fill")
                .font(.headline)
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: model.isLoading ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func panelRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder
    private var vehicleArtworkPreview: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.black.opacity(0.18))
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.snapshot.modelDisplayName)
                        .font(.system(size: 17, weight: .light))
                        .tracking(5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(model.snapshot.trimLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(width: 118, alignment: .leading)

                previewArtwork
                    .frame(width: 162, height: 70, alignment: .center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Text(model.snapshot.statusLine)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
                .padding(8)
        }
        .frame(height: 104)
        .clipped()
    }

    @ViewBuilder
    private var previewArtwork: some View {
        if let url = model.skinImageURL {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                } else {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(model.snapshot.tint)
                }
            }
        } else if let image = model.localSkinImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "car.side.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(model.snapshot.tint)
        }
    }

    private var vehicleIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.snapshot.modelDisplayName)
                    .font(.system(size: 18, weight: .light))
                    .tracking(4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                Text(model.snapshot.trimLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack {
                Text(model.snapshot.odometerLabel)
                Spacer()
                Text("Software: \(model.snapshot.softwareLabel)")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            HStack {
                Text("VIN: \(model.snapshot.vinLabel)")
                Spacer()
                Text(model.snapshot.fsdVersionLabel)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            Text(model.snapshot.releaseNoteLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private func commandButton(_ title: String, _ icon: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isLoading)
    }
}

private struct TeslaMetricTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private final class TeslaChargerModel: ObservableObject {
    @Published private(set) var snapshot = TeslaChargeSnapshot.empty
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    @Published private(set) var hasError = false
    @Published private(set) var skinImageURL: URL?
    @Published private(set) var localSkinImage: NSImage?
    @Published private(set) var skinStatusLabel = "Not configured"

    var hasSkinImage: Bool {
        skinImageURL != nil || localSkinImage != nil
    }

    private let widgetId: String
    private var lastLoopConfig = ""

    init(widgetId: String) {
        self.widgetId = widgetId
    }

    @MainActor
    func runRefreshLoop() async {
        let signature = config.signature
        if signature != lastLoopConfig {
            lastLoopConfig = signature
            await refresh()
        }

        while !Task.isCancelled {
            try? await Task.sleep(for: config.refreshInterval)
            await refresh()
        }
    }

    @MainActor
    func refresh() async {
        let current = config
        loadSkin(from: current)
        guard let request = current.vehicleDataRequest else {
            snapshot = .missingConfig
            message = "Add Fleet API URL, token, and VIN in widget settings."
            hasError = true
            return
        }

        isLoading = true
        hasError = false
        defer { isLoading = false }

        do {
            if current.wakeForRefresh, let wakeRequest = current.wakeRequest {
                _ = try? await TeslaHTTPClient.send(wakeRequest)
            }

            let data = try await sendWithTokenRefresh(request, config: current)
            let optionsData: Data?
            if let optionsRequest = current.optionsRequest {
                optionsData = try? await sendWithTokenRefresh(optionsRequest, config: current)
            } else {
                optionsData = nil
            }
            let releaseNotesData: Data?
            if let releaseNotesRequest = current.releaseNotesRequest {
                releaseNotesData = try? await sendWithTokenRefresh(releaseNotesRequest, config: current)
            } else {
                releaseNotesData = nil
            }
            let parsed = try TeslaVehicleDataParser.parse(
                vehicleData: data,
                optionsData: optionsData,
                releaseNotesData: releaseNotesData,
                vin: current.vin
            )
            TeslaWidgetCache.save(vehicleData: data, optionsData: optionsData, releaseNotesData: releaseNotesData)
            snapshot = parsed
            message = "Live data refreshed."
            hasError = false
        } catch {
            if let cached = TeslaWidgetCache.load() {
                do {
                    snapshot = try TeslaVehicleDataParser.parse(
                        vehicleData: cached.vehicleData,
                        optionsData: cached.optionsData,
                        releaseNotesData: cached.releaseNotesData,
                        vin: current.vin
                    ).withChargingState("Asleep")
                    message = "Vehicle is asleep or offline. Showing last live data."
                    hasError = false
                    return
                } catch {
                    // Fall through to the normal error state if the cache cannot be parsed.
                }
            }

            if (error as? TeslaAPIError)?.isVehicleUnavailable == true {
                snapshot = snapshot.withChargingState("Asleep")
                message = "Vehicle is asleep or offline. Wake it from the Tesla app or enable Wake Vehicle Before Refresh."
                hasError = false
            } else {
                message = error.localizedDescription
                hasError = true
            }
        }
    }

    @MainActor
    func sendCommand(_ command: TeslaChargeCommand) async {
        let current = config
        guard let request = current.commandRequest(command) else {
            message = "Add Fleet API URL, token, and VIN in widget settings."
            hasError = true
            return
        }

        isLoading = true
        hasError = false
        defer { isLoading = false }

        do {
            let data = try await sendWithTokenRefresh(request, config: current)
            let summary = TeslaCommandParser.parse(data)
            message = summary.isEmpty ? "\(command.title) sent." : summary
            hasError = !summary.lowercased().contains("true") && summary.lowercased().contains("error")
            await refresh()
        } catch {
            message = error.localizedDescription
            hasError = true
        }
    }

    private func sendWithTokenRefresh(_ request: URLRequest, config: TeslaChargerConfig) async throws -> Data {
        do {
            return try await TeslaHTTPClient.send(request)
        } catch let error as TeslaAPIError where error.isUnauthorized {
            guard
                let refreshedToken = try await TeslaOAuthClient.refreshAccessToken(config: config),
                let retry = config.replacingAccessToken(refreshedToken).request(from: request)
            else {
                throw error
            }
            return try await TeslaHTTPClient.send(retry)
        }
    }

    private var config: TeslaChargerConfig {
        TeslaChargerConfig(widgetId: widgetId)
    }

    private func loadSkin(from config: TeslaChargerConfig) {
        skinImageURL = config.skinImageURL

        guard let path = config.skinImagePath else {
            localSkinImage = nil
            skinStatusLabel = skinImageURL == nil ? "Not configured" : "URL"
            return
        }

        if let image = NSImage(contentsOfFile: path) {
            localSkinImage = image
            skinStatusLabel = path.contains("tesla-api-render") ? "Tesla API render" : "Local image"
        } else {
            localSkinImage = nil
            skinStatusLabel = skinImageURL == nil ? "Missing local image" : "URL fallback"
        }
    }
}

private struct TeslaChargerConfig {
    static let defaultBaseURL = "https://fleet-api.prd.na.vn.cloud.tesla.com"
    static let tokenURL = "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token"

    let baseURL: String
    var accessToken: String
    let refreshToken: String
    let clientId: String
    let vin: String
    let skinImageURL: URL?
    let skinImagePath: String?
    let refreshInterval: Duration
    let wakeForRefresh: Bool

    init(widgetId: String) {
        baseURL = WidgetDefaults.string(key: "apiBaseURL", widgetId: widgetId, default: Self.defaultBaseURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        accessToken = WidgetDefaults.string(key: "accessToken", widgetId: widgetId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        refreshToken = WidgetDefaults.string(key: "refreshToken", widgetId: widgetId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        clientId = WidgetDefaults.string(key: "clientId", widgetId: widgetId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        vin = WidgetDefaults.string(key: "vehicleVin", widgetId: widgetId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let skinURLString = WidgetDefaults.string(key: "skinImageURL", widgetId: widgetId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        skinImageURL = skinURLString.isEmpty ? nil : URL(string: skinURLString)
        let skinPathString = WidgetDefaults.string(key: "skinImagePath", widgetId: widgetId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        skinImagePath = skinPathString.isEmpty
            ? nil
            : NSString(string: skinPathString).expandingTildeInPath
        let seconds = max(30, Int(WidgetDefaults.double(key: "refreshInterval", widgetId: widgetId, default: 120)))
        refreshInterval = .seconds(seconds)
        wakeForRefresh = WidgetDefaults.bool(key: "wakeForRefresh", widgetId: widgetId, default: false)
    }

    var signature: String {
        "\(baseURL)|\(vin)|\(refreshInterval)|\(wakeForRefresh)|\(skinImageURL?.absoluteString ?? "")|\(skinImagePath ?? "")|\(accessToken.isEmpty ? "empty" : "token")|\(refreshToken.isEmpty ? "empty" : "refresh")|\(clientId.isEmpty ? "empty" : "client")"
    }

    var vehicleDataRequest: URLRequest? {
        request(path: "/api/1/vehicles/\(vin)/vehicle_data", method: "GET")
    }

    var wakeRequest: URLRequest? {
        request(path: "/api/1/vehicles/\(vin)/wake_up", method: "POST")
    }

    var optionsRequest: URLRequest? {
        request(path: "/api/1/dx/vehicles/options?vin=\(vin)", method: "GET")
    }

    var releaseNotesRequest: URLRequest? {
        request(path: "/api/1/vehicles/\(vin)/release_notes", method: "GET")
    }

    func commandRequest(_ command: TeslaChargeCommand) -> URLRequest? {
        request(path: "/api/1/vehicles/\(vin)/command/\(command.endpoint)", method: "POST", body: command.body)
    }

    private func request(path: String, method: String, body: [String: Any]? = nil) -> URLRequest? {
        guard !baseURL.isEmpty, !accessToken.isEmpty, !vin.isEmpty else { return nil }
        guard let url = URL(string: baseURL + path) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken.removingBearerPrefix)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    func replacingAccessToken(_ token: String) -> TeslaChargerConfig {
        var copy = self
        copy.accessToken = token
        return copy
    }

    func request(from request: URLRequest) -> URLRequest? {
        guard !accessToken.isEmpty else { return nil }
        var retry = request
        retry.setValue("Bearer \(accessToken.removingBearerPrefix)", forHTTPHeaderField: "Authorization")
        return retry
    }
}

private enum TeslaChargeCommand {
    case startCharging
    case stopCharging
    case openChargePort
    case setChargeLimit(Int)
    case setChargingAmps(Int)

    var title: String {
        switch self {
        case .startCharging: return "Start charging"
        case .stopCharging: return "Stop charging"
        case .openChargePort: return "Open charge port"
        case .setChargeLimit: return "Set charge limit"
        case .setChargingAmps: return "Set charging amps"
        }
    }

    var endpoint: String {
        switch self {
        case .startCharging: return "charge_start"
        case .stopCharging: return "charge_stop"
        case .openChargePort: return "charge_port_door_open"
        case .setChargeLimit: return "set_charge_limit"
        case .setChargingAmps: return "set_charging_amps"
        }
    }

    var body: [String: Any]? {
        switch self {
        case .setChargeLimit(let percent):
            return ["percent": percent]
        case .setChargingAmps(let amps):
            return ["charging_amps": amps]
        default:
            return nil
        }
    }
}

private struct TeslaChargeSnapshot {
    var vehicleName: String
    var modelDisplayName: String
    var trimLabel: String
    var vin: String?
    var odometerMiles: Double?
    var softwareVersion: String?
    var fsdPackage: String?
    var fsdSoftwareVersion: String?
    var releaseNoteVersion: String?
    var releaseNoteTitle: String?
    var batteryLevel: Int?
    var chargeLimit: Int?
    var chargingState: String
    var chargerPower: Double?
    var chargerVoltage: Double?
    var chargingAmps: Int?
    var minutesToFull: Int?
    var energyAdded: Double?
    var updatedAt: Date?

    static let empty = TeslaChargeSnapshot(
        vehicleName: "Tesla",
        modelDisplayName: "MODEL 3",
        trimLabel: "Vehicle details",
        vin: nil,
        odometerMiles: nil,
        softwareVersion: nil,
        fsdPackage: nil,
        fsdSoftwareVersion: nil,
        releaseNoteVersion: nil,
        releaseNoteTitle: nil,
        batteryLevel: nil,
        chargeLimit: nil,
        chargingState: "Waiting",
        chargerPower: nil,
        chargerVoltage: nil,
        chargingAmps: nil,
        minutesToFull: nil,
        energyAdded: nil,
        updatedAt: nil
    )

    static let missingConfig = TeslaChargeSnapshot(
        vehicleName: "Setup",
        modelDisplayName: "MODEL 3",
        trimLabel: "Needs setup",
        vin: nil,
        odometerMiles: nil,
        softwareVersion: nil,
        fsdPackage: nil,
        fsdSoftwareVersion: nil,
        releaseNoteVersion: nil,
        releaseNoteTitle: nil,
        batteryLevel: nil,
        chargeLimit: nil,
        chargingState: "Needs token",
        chargerPower: nil,
        chargerVoltage: nil,
        chargingAmps: nil,
        minutesToFull: nil,
        energyAdded: nil,
        updatedAt: nil
    )

    var batteryFraction: CGFloat {
        CGFloat(max(0, min(100, batteryLevel ?? 0))) / 100
    }

    var batteryLabel: String {
        batteryLevel.map { "\($0)%" } ?? "--"
    }

    var limitLabel: String {
        chargeLimit.map { "\($0)%" } ?? "--"
    }

    var powerLabel: String {
        guard let chargerPower else { return "--" }
        return chargerPower >= 1 ? String(format: "%.0f kW", chargerPower) : String(format: "%.1f kW", chargerPower)
    }

    var currentLabel: String {
        let amps = chargingAmps.map { "\($0) A" } ?? "--"
        let volts = chargerVoltage.map { String(format: "%.0f V", $0) } ?? "--"
        return "\(amps) / \(volts)"
    }

    var energyAddedLabel: String {
        guard let energyAdded else { return "--" }
        return String(format: "%.1f kWh", energyAdded)
    }

    var odometerLabel: String {
        guard let odometerMiles else { return "-- miles" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let miles = formatter.string(from: NSNumber(value: odometerMiles)) ?? String(format: "%.0f", odometerMiles)
        return "\(miles) miles"
    }

    var softwareLabel: String {
        softwareVersion?.trimmedNonEmpty ?? "--"
    }

    var vinLabel: String {
        vin?.trimmedNonEmpty ?? "--"
    }

    var fsdLabel: String {
        fsdPackage?.replacingOccurrences(of: "Full Self-Driving ", with: "FSD ") ?? "--"
    }

    var fsdVersionLabel: String {
        if let fsdSoftwareVersion = fsdSoftwareVersion?.trimmedNonEmpty {
            return "FSD: \(fsdSoftwareVersion)"
        }
        if fsdPackage != nil {
            return "FSD version unavailable"
        }
        return "FSD: --"
    }

    var releaseNoteLabel: String {
        guard let releaseNoteTitle = releaseNoteTitle?.trimmedNonEmpty else {
            return "Release notes: --"
        }
        if let releaseNoteVersion = releaseNoteVersion?.trimmedNonEmpty {
            return "\(releaseNoteVersion): \(releaseNoteTitle)"
        }
        return releaseNoteTitle
    }

    var statusLine: String {
        if let minutesToFull, minutesToFull > 0, isCharging {
            return "\(chargingState) - \(minutesToFull) min"
        }
        return chargingState
    }

    var updatedLabel: String {
        guard let updatedAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    var isCharging: Bool {
        chargingState.lowercased().contains("charging")
    }

    var tint: Color {
        if isCharging { return .green }
        if (batteryLevel ?? 0) < 20 { return .red }
        return .cyan
    }

    var icon: String {
        if isCharging { return "bolt.fill" }
        if (batteryLevel ?? 0) < 20 { return "battery.25percent" }
        return "bolt.car.fill"
    }

    func withChargingState(_ state: String) -> TeslaChargeSnapshot {
        var copy = self
        copy.chargingState = state
        return copy
    }
}

private enum TeslaVehicleDataParser {
    static func parse(vehicleData data: Data, optionsData: Data?, releaseNotesData: Data?, vin: String) throws -> TeslaChargeSnapshot {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let response = root["response"] as? [String: Any]
        else {
            throw TeslaAPIError.invalidResponse
        }

        let chargeState = response["charge_state"] as? [String: Any] ?? [:]
        let vehicleState = response["vehicle_state"] as? [String: Any] ?? [:]
        let vehicleConfig = response["vehicle_config"] as? [String: Any] ?? [:]
        let activeOptions = parseActiveOptions(optionsData)
        let releaseNote = parseLatestReleaseNote(releaseNotesData)

        return TeslaChargeSnapshot(
            vehicleName: string(vehicleState["vehicle_name"])
                ?? string(response["display_name"])
                ?? "Tesla",
            modelDisplayName: modelDisplayName(carType: string(vehicleConfig["car_type"])),
            trimLabel: trimLabel(vehicleConfig: vehicleConfig, activeOptions: activeOptions),
            vin: vin,
            odometerMiles: double(vehicleState["odometer"]),
            softwareVersion: softwareVersion(from: vehicleState),
            fsdPackage: activeOptions.first { $0.code == "APF2" || $0.displayName.localizedCaseInsensitiveContains("Full Self-Driving") }?.displayName,
            fsdSoftwareVersion: fsdSoftwareVersion(from: vehicleState),
            releaseNoteVersion: releaseNote?.version,
            releaseNoteTitle: releaseNote?.title,
            batteryLevel: int(chargeState["battery_level"]),
            chargeLimit: int(chargeState["charge_limit_soc"]),
            chargingState: string(chargeState["charging_state"]) ?? "Unknown",
            chargerPower: double(chargeState["charger_power"]),
            chargerVoltage: double(chargeState["charger_voltage"]),
            chargingAmps: int(chargeState["charger_actual_current"]),
            minutesToFull: int(chargeState["minutes_to_full_charge"]),
            energyAdded: double(chargeState["charge_energy_added"]),
            updatedAt: Date()
        )
    }

    private static func parseActiveOptions(_ data: Data?) -> [TeslaOption] {
        guard
            let data,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let codes = root["codes"] as? [[String: Any]]
        else {
            return []
        }

        return codes.compactMap { item in
            guard
                (item["isActive"] as? Bool) == true,
                let code = string(item["code"])?.replacingOccurrences(of: "$", with: ""),
                let displayName = string(item["displayName"])?.trimmedNonEmpty
            else {
                return nil
            }
            return TeslaOption(code: code, displayName: displayName)
        }
    }

    private static func parseLatestReleaseNote(_ data: Data?) -> TeslaReleaseNote? {
        guard
            let data,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let response = root["response"] as? [String: Any],
            let notes = response["release_notes"] as? [[String: Any]]
        else {
            return nil
        }

        return notes.compactMap { item in
            guard let title = string(item["title"])?.trimmedNonEmpty else { return nil }
            return TeslaReleaseNote(
                version: string(item["customer_version"])?.trimmedNonEmpty,
                title: title
            )
        }.first
    }

    private static func modelDisplayName(carType: String?) -> String {
        switch carType {
        case "model3": return "MODEL 3"
        case "modely": return "MODEL Y"
        case "models": return "MODEL S"
        case "modelx": return "MODEL X"
        default: return "MODEL 3"
        }
    }

    private static func trimLabel(vehicleConfig: [String: Any], activeOptions: [TeslaOption]) -> String {
        if let trim = activeOptions.first(where: { $0.code.hasPrefix("MT") })?.displayName {
            return trim
                .replacingOccurrences(of: " Rear-Wheel Drive", with: "")
                .replacingOccurrences(of: " All-Wheel Drive", with: "")
        }

        if string(vehicleConfig["trim_badging"]) == "50" || int(vehicleConfig["trim_badging"]) == 50 {
            return "Standard Range Plus"
        }

        return "Vehicle"
    }

    private static func softwareVersion(from vehicleState: [String: Any]) -> String? {
        string(vehicleState["car_version"])?.components(separatedBy: " ").first?.trimmedNonEmpty
    }

    private static func fsdSoftwareVersion(from vehicleState: [String: Any]) -> String? {
        let candidateKeys = [
            "fsd_version",
            "full_self_driving_version",
            "full_self_driving_software_version",
            "autopilot_version",
        ]
        for key in candidateKeys {
            if let value = string(vehicleState[key])?.trimmedNonEmpty {
                return value
            }
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

private struct TeslaOption {
    let code: String
    let displayName: String
}

private struct TeslaReleaseNote {
    let version: String?
    let title: String
}

private struct TeslaWidgetCache {
    let vehicleData: Data
    let optionsData: Data?
    let releaseNotesData: Data?

    static func save(vehicleData: Data, optionsData: Data?, releaseNotesData: Data?) {
        do {
            let directory = try cacheDirectory()
            try vehicleData.write(to: directory.appendingPathComponent("vehicle-data.json"), options: .atomic)
            if let optionsData {
                try optionsData.write(to: directory.appendingPathComponent("vehicle-options.json"), options: .atomic)
            }
            if let releaseNotesData {
                try releaseNotesData.write(to: directory.appendingPathComponent("release-notes.json"), options: .atomic)
            }
        } catch {
            // Cache failures should never break live widget refreshes.
        }
    }

    static func load() -> TeslaWidgetCache? {
        do {
            let directory = try cacheDirectory()
            let vehicleData = try Data(contentsOf: directory.appendingPathComponent("vehicle-data.json"))
            let optionsURL = directory.appendingPathComponent("vehicle-options.json")
            let notesURL = directory.appendingPathComponent("release-notes.json")
            return TeslaWidgetCache(
                vehicleData: vehicleData,
                optionsData: try? Data(contentsOf: optionsURL),
                releaseNotesData: try? Data(contentsOf: notesURL)
            )
        } catch {
            return nil
        }
    }

    private static func cacheDirectory() throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DDP Tesla Charger Widget/cache", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private enum TeslaCommandParser {
    static func parse(_ data: Data) -> String {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return "Command response received."
        }

        if let response = root["response"] as? [String: Any] {
            let result = response["result"].map { "\($0)" } ?? "unknown"
            let reason = response["reason"].map { ": \($0)" } ?? ""
            return "Command result \(result)\(reason)"
        }

        if let error = root["error"] {
            return "Command error: \(error)"
        }

        return "Command response received."
    }
}

private enum TeslaHTTPClient {
    static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TeslaAPIError.invalidResponse
        }

        guard 200..<300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw TeslaAPIError.http(status: http.statusCode, body: body)
        }

        return data
    }
}

private enum TeslaOAuthClient {
    static func refreshAccessToken(config: TeslaChargerConfig) async throws -> String? {
        guard
            !config.clientId.isEmpty,
            !config.refreshToken.isEmpty,
            let url = URL(string: TeslaChargerConfig.tokenURL)
        else {
            return nil
        }

        let parameters = [
            "grant_type": "refresh_token",
            "client_id": config.clientId,
            "refresh_token": config.refreshToken,
        ]
        let body = parameters
            .map { "\($0.key.urlFormEncoded)=\($0.value.urlFormEncoded)" }
            .joined(separator: "&")
            .data(using: .utf8)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await TeslaHTTPClient.send(request)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = root["access_token"] as? String,
            !accessToken.isEmpty
        else {
            return nil
        }

        UserDefaults.standard.set(accessToken, forKey: "widget.tesla-charger.accessToken")
        if let refreshToken = root["refresh_token"] as? String, !refreshToken.isEmpty {
            UserDefaults.standard.set(refreshToken, forKey: "widget.tesla-charger.refreshToken")
        }
        return accessToken
    }
}

private enum TeslaAPIError: LocalizedError {
    case invalidResponse
    case http(status: Int, body: String)

    var isVehicleUnavailable: Bool {
        switch self {
        case .http(let status, let body):
            let lowercasedBody = body.lowercased()
            return status == 408 || lowercasedBody.contains("vehicle unavailable") || lowercasedBody.contains("offline or asleep")
        case .invalidResponse:
            return false
        }
    }

    var isUnauthorized: Bool {
        switch self {
        case .http(let status, _):
            return status == 401 || status == 403
        case .invalidResponse:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Tesla API returned an unreadable response."
        case .http(let status, let body):
            return "Tesla API HTTP \(status): \(body.prefix(160))"
        }
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }

    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var removingBearerPrefix: String {
        if lowercased().hasPrefix("bearer ") {
            return String(dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return self
    }
}
