import Foundation

enum AppConfig {
    static let isBackendEnabled = true
    static let backendBaseURL = "https://stib-alert-backend.onrender.com"
    static let backendDisabledMessage = "Backend iOS tijdelijk uitgeschakeld"
    static let googleMaps3DAPIKey = (Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_3D_API_KEY") as? String) ?? ""
}
