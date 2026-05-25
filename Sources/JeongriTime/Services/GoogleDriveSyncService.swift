import AuthenticationServices
import CryptoKit
import Foundation

enum GoogleDriveSyncError: LocalizedError {
    case missingClientID
    case missingDeviceCode
    case authorizationPending
    case slowDown
    case accessDenied
    case missingToken
    case invalidResponse
    case uploadFailed
    case browserLoginFailed
    case redirectURIMissing

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Google OAuth Client ID가 필요합니다."
        case .missingDeviceCode:
            return "먼저 로그인 코드를 받아야 합니다."
        case .authorizationPending:
            return "아직 Google 승인이 완료되지 않았습니다."
        case .slowDown:
            return "Google 요청 간격을 조금 늦춰야 합니다."
        case .accessDenied:
            return "Google Drive 접근이 허용되지 않았습니다."
        case .missingToken:
            return "Google 로그인 정보가 없습니다."
        case .invalidResponse:
            return "Google Drive 응답을 읽지 못했습니다."
        case .uploadFailed:
            return "Google Drive에 동기화 파일을 저장하지 못했습니다."
        case .browserLoginFailed:
            return "Google 로그인 응답을 처리하지 못했습니다."
        case .redirectURIMissing:
            return "Client ID에서 Google 리디렉트 URI를 만들지 못했습니다."
        }
    }
}

struct GoogleDriveAuthToken: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date

    var isRefreshNeeded: Bool {
        Date() > expiresAt.addingTimeInterval(-120)
    }
}

private struct GoogleDeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURL = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct GoogleTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct GoogleErrorResponse: Decodable {
    let error: String
}

private struct GoogleDriveFileList: Decodable {
    let files: [GoogleDriveFile]
}

private struct GoogleDriveFile: Decodable {
    let id: String
    let name: String?
}

@MainActor
final class GoogleDriveSyncService: ObservableObject {
    @Published private(set) var clientID: String
    @Published private(set) var statusText: String
    @Published private(set) var message: String?
    @Published private(set) var userCode: String?
    @Published private(set) var verificationURL: URL?
    @Published private(set) var isSynchronizing = false
    @Published private(set) var lastSyncDate: Date?

    private let defaults: UserDefaults
    private let clientIDKey = "JeongriTime.googleDrive.clientID"
    private let tokenKey = "JeongriTime.googleDrive.token"
    private let fileIDKey = "JeongriTime.googleDrive.fileID"
    private let lastSyncKey = "JeongriTime.googleDrive.lastSync"
    private let syncFileName = "jeongri-time-sync.json"
    private let scope = "https://www.googleapis.com/auth/drive.appdata"
    private var token: GoogleDriveAuthToken?
    private var deviceCode: String?
    private var pollInterval = 5
    private var lastAttemptedSyncDate: Date?

    var isConfigured: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isAuthorized: Bool {
        token != nil
    }

    var redirectURIText: String? {
        browserRedirectURI
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.clientID = defaults.string(forKey: clientIDKey) ?? ""
        self.token = Self.loadToken(defaults: defaults, key: tokenKey)
        self.lastSyncDate = defaults.object(forKey: lastSyncKey) as? Date
        self.statusText = token == nil ? "로그인 필요" : "대기 중"
    }

    func saveClientID(_ value: String) {
        clientID = value.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(clientID, forKey: clientIDKey)
        message = clientID.isEmpty ? "Google OAuth Client ID가 비어 있습니다." : "Google OAuth Client ID를 저장했습니다."
    }

    func signOut() {
        token = nil
        deviceCode = nil
        userCode = nil
        verificationURL = nil
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: fileIDKey)
        statusText = "로그인 필요"
        message = "Google Drive 연결을 해제했습니다."
    }

    func requestDeviceCode() async {
        guard isConfigured else {
            message = GoogleDriveSyncError.missingClientID.localizedDescription
            return
        }

        statusText = "로그인 준비 중"
        do {
            let request = try formRequest(
                url: URL(string: "https://oauth2.googleapis.com/device/code")!,
                parameters: [
                    "client_id": clientID,
                    "scope": scope
                ]
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)
            let decoded = try JSONDecoder().decode(GoogleDeviceCodeResponse.self, from: data)
            deviceCode = decoded.deviceCode
            userCode = decoded.userCode
            verificationURL = decoded.verificationURL
            pollInterval = max(decoded.interval, 5)
            statusText = "승인 대기"
            message = "\(decoded.verificationURL.absoluteString)에서 \(decoded.userCode)를 입력하세요."
        } catch {
            statusText = "로그인 실패"
            message = error.localizedDescription
        }
    }

    func signInWithGoogle() async {
        guard isConfigured else {
            message = GoogleDriveSyncError.missingClientID.localizedDescription
            return
        }
        guard let redirectURI = browserRedirectURI,
              let callbackScheme = URL(string: redirectURI)?.scheme
        else {
            message = GoogleDriveSyncError.redirectURIMissing.localizedDescription
            return
        }

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authorizationURL = components.url else {
            message = GoogleDriveSyncError.browserLoginFailed.localizedDescription
            return
        }

        statusText = "로그인 중"
        do {
            let callbackURL = try await authenticate(url: authorizationURL, callbackScheme: callbackScheme)
            let received = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
            guard received?.queryItems?.first(where: { $0.name == "state" })?.value == state,
                  let code = received?.queryItems?.first(where: { $0.name == "code" })?.value
            else {
                throw GoogleDriveSyncError.browserLoginFailed
            }

            try await exchangeAuthorizationCode(code, redirectURI: redirectURI, codeVerifier: verifier)
            statusText = "연결됨"
            message = "Google 로그인이 완료됐습니다."
        } catch {
            statusText = "로그인 실패"
            message = error.localizedDescription
        }
    }

    func pollForToken() async {
        guard isConfigured else {
            message = GoogleDriveSyncError.missingClientID.localizedDescription
            return
        }
        guard let deviceCode else {
            message = GoogleDriveSyncError.missingDeviceCode.localizedDescription
            return
        }

        statusText = "승인 확인 중"
        do {
            let request = try formRequest(
                url: URL(string: "https://oauth2.googleapis.com/token")!,
                parameters: [
                    "client_id": clientID,
                    "device_code": deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
                ]
            )
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                if let googleError = try? JSONDecoder().decode(GoogleErrorResponse.self, from: data) {
                    switch googleError.error {
                    case "authorization_pending":
                        throw GoogleDriveSyncError.authorizationPending
                    case "slow_down":
                        pollInterval += 5
                        throw GoogleDriveSyncError.slowDown
                    case "access_denied":
                        throw GoogleDriveSyncError.accessDenied
                    default:
                        throw GoogleDriveSyncError.invalidResponse
                    }
                }
                throw GoogleDriveSyncError.invalidResponse
            }

            let decoded = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
            let newToken = GoogleDriveAuthToken(
                accessToken: decoded.accessToken,
                refreshToken: decoded.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
            )
            token = newToken
            persistToken(newToken)
            userCode = nil
            verificationURL = nil
            self.deviceCode = nil
            statusText = "연결됨"
            message = "Google Drive 연결이 완료됐습니다."
        } catch {
            statusText = "승인 대기"
            message = error.localizedDescription
        }
    }

    func synchronizeIfReady(store: ScheduleStore, minimumInterval: TimeInterval = 60) async {
        guard isConfigured, token != nil, !isSynchronizing else {
            return
        }
        if let lastAttemptedSyncDate, Date().timeIntervalSince(lastAttemptedSyncDate) < minimumInterval {
            return
        }
        await synchronize(store: store)
    }

    func synchronize(store: ScheduleStore) async {
        guard isConfigured else {
            message = GoogleDriveSyncError.missingClientID.localizedDescription
            return
        }
        guard token != nil else {
            message = "먼저 Google Drive에 로그인하세요."
            statusText = "로그인 필요"
            return
        }
        guard !isSynchronizing else {
            return
        }

        isSynchronizing = true
        lastAttemptedSyncDate = Date()
        statusText = "동기화 중"

        do {
            let accessToken = try await validAccessToken()
            let remoteSnapshot = try await downloadSnapshot(accessToken: accessToken)
            if let remoteSnapshot {
                store.applySyncSnapshot(remoteSnapshot)
            }
            try await uploadSnapshot(store.makeSyncSnapshot(), accessToken: accessToken)
            lastSyncDate = Date()
            defaults.set(lastSyncDate, forKey: lastSyncKey)
            statusText = "동기화됨"
            message = "Google Drive 동기화를 마쳤습니다."
        } catch {
            statusText = "동기화 실패"
            message = error.localizedDescription
        }

        isSynchronizing = false
    }

    private func validAccessToken() async throws -> String {
        guard let current = token else {
            throw GoogleDriveSyncError.missingToken
        }
        guard current.isRefreshNeeded else {
            return current.accessToken
        }
        guard let refreshToken = current.refreshToken else {
            throw GoogleDriveSyncError.missingToken
        }

        let request = try formRequest(
            url: URL(string: "https://oauth2.googleapis.com/token")!,
            parameters: [
                "client_id": clientID,
                "refresh_token": refreshToken,
                "grant_type": "refresh_token"
            ]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        let refreshed = GoogleDriveAuthToken(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
        )
        token = refreshed
        persistToken(refreshed)
        return refreshed.accessToken
    }

    private func exchangeAuthorizationCode(_ code: String, redirectURI: String, codeVerifier: String) async throws {
        let request = try formRequest(
            url: URL(string: "https://oauth2.googleapis.com/token")!,
            parameters: [
                "client_id": clientID,
                "code": code,
                "code_verifier": codeVerifier,
                "grant_type": "authorization_code",
                "redirect_uri": redirectURI
            ]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        let newToken = GoogleDriveAuthToken(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
        )
        token = newToken
        persistToken(newToken)
        userCode = nil
        verificationURL = nil
        deviceCode = nil
    }

    private func downloadSnapshot(accessToken: String) async throws -> ScheduleSyncSnapshot? {
        guard let fileID = try await syncFileID(accessToken: accessToken) else {
            return nil
        }

        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ScheduleSyncSnapshot.self, from: data)
    }

    private func uploadSnapshot(_ snapshot: ScheduleSyncSnapshot, accessToken: String) async throws {
        let data = try JSONEncoder().encode(snapshot)
        if let fileID = try await syncFileID(accessToken: accessToken) {
            try await updateFile(id: fileID, data: data, accessToken: accessToken)
        } else {
            let newFileID = try await createFile(data: data, accessToken: accessToken)
            defaults.set(newFileID, forKey: fileIDKey)
        }
    }

    private func syncFileID(accessToken: String) async throws -> String? {
        if let cached = defaults.string(forKey: fileIDKey), !cached.isEmpty {
            return cached
        }

        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "spaces", value: "appDataFolder"),
            URLQueryItem(name: "q", value: "name='\(syncFileName)' and trashed=false"),
            URLQueryItem(name: "fields", value: "files(id,name)")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(GoogleDriveFileList.self, from: data)
        let fileID = decoded.files.first?.id
        if let fileID {
            defaults.set(fileID, forKey: fileIDKey)
        }
        return fileID
    }

    private func updateFile(id: String, data: Data, accessToken: String) async throws {
        var components = URLComponents(string: "https://www.googleapis.com/upload/drive/v3/files/\(id)")!
        components.queryItems = [URLQueryItem(name: "uploadType", value: "media")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: Data())
    }

    private func createFile(data: Data, accessToken: String) async throws -> String {
        let boundary = "JeongriTimeBoundary\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, data: data)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: responseData)
        guard let file = try? JSONDecoder().decode(GoogleDriveFile.self, from: responseData) else {
            throw GoogleDriveSyncError.uploadFailed
        }
        return file.id
    }

    private func formRequest(url: URL, parameters: [String: String]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters
            .map { "\($0.key.urlFormEncoded)=\($0.value.urlFormEncoded)" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }

    private func multipartBody(boundary: String, data: Data) -> Data {
        let metadata = """
        {"name":"\(syncFileName)","parents":["appDataFolder"],"mimeType":"application/json"}
        """
        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.appendString(metadata)
        body.appendString("\r\n--\(boundary)\r\n")
        body.appendString("Content-Type: application/json\r\n\r\n")
        body.append(data)
        body.appendString("\r\n--\(boundary)--\r\n")
        return body
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GoogleDriveSyncError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let googleError = try? JSONDecoder().decode(GoogleErrorResponse.self, from: data) {
                if googleError.error == "invalid_grant" {
                    throw GoogleDriveSyncError.missingToken
                }
            }
            throw GoogleDriveSyncError.invalidResponse
        }
    }

    private func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await GoogleWebAuthenticator.authenticate(url: url, callbackScheme: callbackScheme)
    }

    private var browserRedirectURI: String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else {
            return nil
        }
        let prefix = String(clientID.dropLast(suffix.count))
        guard !prefix.isEmpty else {
            return nil
        }
        return "com.googleusercontent.apps.\(prefix):/oauth2redirect"
    }

    private static func makeCodeVerifier() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<64).map { _ in characters[Int.random(in: 0..<characters.count)] })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func persistToken(_ token: GoogleDriveAuthToken) {
        if let data = try? JSONEncoder().encode(token) {
            defaults.set(data, forKey: tokenKey)
        }
    }

    private static func loadToken(defaults: UserDefaults, key: String) -> GoogleDriveAuthToken? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(GoogleDriveAuthToken.self, from: data)
    }
}

private enum GoogleWebAuthenticator {
    @MainActor
    static func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let holder = AuthenticationSessionHolder()
            let completionHandler = makeCompletionHandler(continuation: continuation, holder: holder)
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme,
                completionHandler: completionHandler
            )
            session.presentationContextProvider = GoogleDrivePresentationAnchorProvider.shared
            session.prefersEphemeralWebBrowserSession = false
            holder.retain(session)
            if !session.start() {
                holder.release()
                continuation.resume(throwing: GoogleDriveSyncError.browserLoginFailed)
            }
        }
    }

    private nonisolated static func makeCompletionHandler(
        continuation: CheckedContinuation<URL, any Error>,
        holder: AuthenticationSessionHolder
    ) -> (URL?, (any Error)?) -> Void {
        { callbackURL, error in
            holder.release()
            if let callbackURL {
                continuation.resume(returning: callbackURL)
            } else {
                continuation.resume(throwing: error ?? GoogleDriveSyncError.browserLoginFailed)
            }
        }
    }
}

private final class AuthenticationSessionHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var session: ASWebAuthenticationSession?

    func retain(_ session: ASWebAuthenticationSession) {
        lock.withLock {
            self.session = session
        }
    }

    func release() {
        lock.withLock {
            session = nil
        }
    }
}

private final class GoogleDrivePresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleDrivePresentationAnchorProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }
}

private extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return allowed
    }()
}
