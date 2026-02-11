import Foundation

struct AppConfig {
    static let supabaseUrl = "https://epfcaibrywkberynrvbk.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwZmNhaWJyeXdrYmVyeW5ydmJrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAwNDg4MTMsImV4cCI6MjA4NTYyNDgxM30.E5YhJNMLsggJJ3CuH2Es0V2QfOoUPVFm7J3H2GB9FuQ"
    static let kakaoRestApiKey = "a47c4fab1f9fef87621626c133e93422"
    static var kakaoNativeAppKey: String {
        Bundle.main.object(forInfoDictionaryKey: "KAKAO_NATIVE_APP_KEY") as? String ?? ""
    }
}
