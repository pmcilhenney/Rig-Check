import Foundation

final class SmarterMailService {

    // MARK: - Singleton
    static let shared = SmarterMailService()
    private init() {}

    // MARK: - Config (Info.plist)
    private var baseURL: URL {
        guard
            let s = Bundle.main.object(forInfoDictionaryKey: "SmarterMailBaseURL") as? String,
            let u = URL(string: s)
        else { fatalError("SmarterMailBaseURL missing or invalid in Info.plist") }
        return u
    }

    private var username: String {
        guard let v = Bundle.main.object(forInfoDictionaryKey: "SmarterMailUsername") as? String
        else { fatalError("SmarterMailUsername missing in Info.plist") }
        return v
    }

    private var password: String {
        guard let v = Bundle.main.object(forInfoDictionaryKey: "SmarterMailPassword") as? String
        else { fatalError("SmarterMailPassword missing in Info.plist") }
        return v
    }

    // Optional: only used if we must construct a public URL by hand
    private var publicBaseURL: URL? {
        guard
            let s = Bundle.main.object(forInfoDictionaryKey: "SmarterMailPublicBase") as? String,
            !s.isEmpty,
            let u = URL(string: s)
        else { return nil }
        return u
    }

    // MARK: - Token cache
    private struct TokenPayload {
        let accessToken: String
        let refreshToken: String
        let accessTokenExp: Date
        let refreshTokenExp: Date
    }
    private var token: TokenPayload?
    private let tokenSkew: TimeInterval = 30

    // MARK: - Public API (back-compat for AEDCheckView)
    /// Uploads the file, makes it public, and returns a public URL string.
    func uploadFile(
        toFolder: String,
        fileName: String,
        fileData: Data,
        contentType: String
    ) async throws -> String {
        return try await uploadAndPublish(
            toFolder: toFolder,
            ownerEmail: username,
            fileName: fileName,
            fileData: fileData,
            contentType: contentType,
            shortLink: sanitizeShortLink(from: fileName)
        )
    }

    // MARK: - High-level flow
    private func uploadAndPublish(
        toFolder: String,
        ownerEmail: String,
        fileName: String,
        fileData: Data,
        contentType: String,
        shortLink: String
    ) async throws -> String {

        // 1) Auth
        let bearer = try await ensureAccessToken()

        // 2) Create/confirm folder (idempotent)
        try await ensureFolderExists(folder: toFolder, ownerEmail: ownerEmail, bearer: bearer)

        // 3) Upload (multipart/form-data) — mirrors your working curl
        let uploadEnv = try await uploadMultipart(
            folder: toFolder,
            ownerEmail: ownerEmail,
            fileName: fileName,
            contentType: contentType,
            data: fileData,
            bearer: bearer
        )

        // 4) Resolve GUID (from response first, then via folder listing)
        let fileIds = try await resolveFileIds(
            uploadEnv: uploadEnv,
            folder: toFolder,
            fileName: fileName,
            ownerEmail: ownerEmail,
            bearer: bearer
        )

        // 5) Publish (/{id}/edit)
        try await publishFile(ids: fileIds, shortLink: shortLink, bearer: bearer)

        // 6) Re-list to fetch the definitive publicDownloadLink
        if let info = try await fetchFileInfoGET(folder: toFolder, fileName: fileName, bearer: bearer),
           let path = info.publicDownloadLink, !path.isEmpty,
           let absolute = URL(string: path, relativeTo: baseURL)?.absoluteString {
            return absolute
        }
        if let info = try await fetchFileInfoPOST(folder: toFolder, fileName: fileName, bearer: bearer),
           let path = info.publicDownloadLink, !path.isEmpty,
           let absolute = URL(string: path, relativeTo: baseURL)?.absoluteString {
            return absolute
        }
        if let info = try await fetchFileInfoPOSTWithOwner(folder: toFolder, ownerEmail: ownerEmail, fileName: fileName, bearer: bearer),
           let path = info.publicDownloadLink, !path.isEmpty,
           let absolute = URL(string: path, relativeTo: baseURL)?.absoluteString {
            return absolute
        }

        // Last resort: construct predictable link if configured
        if let constructed = fallbackPublicURL(folder: toFolder, file: fileName) {
            return constructed
        }
        return fileName
    }

    // MARK: - Models
    private struct UploadEnvelope: Codable {
        let uploadResults: [String: Int]?
        let uploadData: [String: UploadItem]?
        let success: Bool?
        let message: String?

        struct UploadItem: Codable {
            let id: String?
            let fileName: String?
            let published: Bool?
            let shortLink: String?
            let publicDownloadLink: String?
            let folderPath: String?
            let encryptedIdString: String?
        }
    }

    private struct FileItem: Codable {
        let id: String?
        let fileName: String?
        let type: String?
        let size: Int?
        let dateAdded: String?
        let published: Bool?
        let version: String?
        let publicDownloadLink: String?
        let shortLink: String?
        let encryptedIdString: String?
        let folderPath: String?
    }

    private struct FolderEnvelope: Codable {
        struct Folder: Codable {
            let name: String?
            let path: String?
            let files: [FileItem]?
        }
        let folder: Folder?
        let success: Bool?
        let message: String?
    }

    // MARK: - Resolve File ID
    private func resolveFileIds(
        uploadEnv: UploadEnvelope,
        folder: String,
        fileName: String,
        ownerEmail: String,
        bearer: String
    ) async throws -> [String] {

        func cleanedIdentifiers(from values: [String?]) -> [String] {
            values.compactMap { value in
                guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                    return nil
                }
                return trimmed
            }
        }

        var collected: [String] = []
        var seen = Set<String>()

        func addIdentifiers(_ values: [String?]) {
            let cleaned = cleanedIdentifiers(from: values)
            for value in cleaned where seen.insert(value).inserted {
                collected.append(value)
            }
        }

        if let dict = uploadEnv.uploadData {
            if let exact = dict.values.first(where: { ($0.fileName ?? "") == fileName }) {
                addIdentifiers([exact.id, exact.encryptedIdString])
            }
            if collected.isEmpty, let any = dict.values.first {
                addIdentifiers([any.id, any.encryptedIdString])
            }
        }

        var needsMoreIdentifiers = collected.count < 2

        if needsMoreIdentifiers, let info = try await fetchFileInfoGET(folder: folder, fileName: fileName, bearer: bearer) {
            addIdentifiers([info.id, info.encryptedIdString])
            needsMoreIdentifiers = collected.count < 2
        }
        if needsMoreIdentifiers, let info = try await fetchFileInfoPOST(folder: folder, fileName: fileName, bearer: bearer) {
            addIdentifiers([info.id, info.encryptedIdString])
            needsMoreIdentifiers = collected.count < 2
        }
        if needsMoreIdentifiers,
           let info = try await fetchFileInfoPOSTWithOwner(
                folder: folder,
                ownerEmail: ownerEmail,
                fileName: fileName,
                bearer: bearer
           ) {
            addIdentifiers([info.id, info.encryptedIdString])
            needsMoreIdentifiers = collected.count < 2
        }

        guard !collected.isEmpty else {
            throw smError("Update failed: upload succeeded but no file GUID was found.")
        }
        return collected
    }

    // MARK: - Auth
    private func ensureAccessToken() async throws -> String {
        if let t = token, t.accessTokenExp.addingTimeInterval(-tokenSkew) > Date() {
            return t.accessToken
        }
        try await authenticate()
        guard let t = token else { throw smError("Auth token missing after login.") }
        return t.accessToken
    }

    private func authenticate() async throws {
        struct AuthReq: Codable { let username: String; let password: String }
        struct AuthResp: Codable {
            let accessToken: String
            let refreshToken: String
            let accessTokenExpiration: String
            let refreshTokenExpiration: String
            let resultCode: Int?
            let success: Bool?
        }

        let url = baseURL.appendingPathComponent("api/v1/auth/authenticate-user")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(AuthReq(username: username, password: password))

        print("🔐 SM auth → \(url.absoluteString) user=\(username)")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw smError("Auth: invalid HTTP response") }
        guard (200...299).contains(http.statusCode) else {
            throw smError("Auth failed \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }

        let decoded = try JSONDecoder().decode(AuthResp.self, from: data)
        guard
            let accessExp = parseISO(decoded.accessTokenExpiration),
            let refreshExp = parseISO(decoded.refreshTokenExpiration)
        else { throw smError("Auth decode failed: invalid expiration dates") }

        token = TokenPayload(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            accessTokenExp: accessExp,
            refreshTokenExp: refreshExp
        )
        print("🧾 SM auth status=\(http.statusCode) (OK)")
    }

    // MARK: - Folder (create if needed)
    private func ensureFolderExists(folder: String, ownerEmail: String, bearer: String) async throws {
        struct Req: Codable {
            let ownerEmailAddress: String
            let folder: String
            let parentFolder: String
        }
        let url = baseURL.appendingPathComponent("api/v1/filestorage/folder-put")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(
            Req(ownerEmailAddress: ownerEmail, folder: folder, parentFolder: "")
        )

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw smError("Folder: invalid response") }
        if !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw smError("Folder create failed \(http.statusCode): \(body)")
        }
    }

    // MARK: - Upload (multipart/form-data)
    private func uploadMultipart(
        folder: String,
        ownerEmail: String,
        fileName: String,
        contentType: String,
        data: Data,
        bearer: String
    ) async throws -> UploadEnvelope {

        let url = baseURL.appendingPathComponent("api/v1/filestorage/upload")

        let boundary = "----rigcheck-\(UUID().uuidString)"
        var body = Data()

        // text fields (exact keys as the working curl command)
        let fields: [String: String] = [
            "ownerEmailAddress": ownerEmail,
            "folder": folder,
            "fileName": fileName,
            "contentType": contentType,
            "createParentFolders": "true",
            "conflictResolution": "replace"
        ]
        for (k, v) in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n")
            body.append("\(v)\r\n")
        }
        // file part
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        print("📤 Uploading to SmarterMail (multipart) → \(url.absoluteString)")
        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw smError("Upload: invalid HTTP response") }
        guard (200...299).contains(http.statusCode) else {
            throw smError("Upload failed \(http.statusCode): \(String(data: respData, encoding: .utf8) ?? "")")
        }

        // Decode but tolerate schema variance
        if let env = try? JSONDecoder().decode(UploadEnvelope.self, from: respData) {
            return env
        } else {
            return UploadEnvelope(uploadResults: nil, uploadData: nil, success: true, message: nil)
        }
    }

    // MARK: - Folder listing (multiple shapes tried)
    /// GET /api/v1/filestorage/folder?path=/folder/
    private func fetchFileInfoGET(folder: String, fileName: String, bearer: String) async throws -> FileItem? {
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/v1/filestorage/folder"),
                                  resolvingAgainstBaseURL: false)
        let pathValue = "/\(folder)/".replacingOccurrences(of: "//", with: "/")
        comps?.queryItems = [URLQueryItem(name: "path", value: pathValue)]
        guard let url = comps?.url else { throw smError("Folder list (GET): bad URL") }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw smError("Folder list (GET): invalid response") }
        guard (200...299).contains(http.statusCode) else {
            // Let caller try POST fallback
            return nil
        }

        let decoded = try JSONDecoder().decode(FolderEnvelope.self, from: data)
        return decoded.folder?.files?.first(where: { ($0.fileName ?? "") == fileName })
    }

    /// POST /api/v1/filestorage/folder  with { "path": "/folder/" }
    private func fetchFileInfoPOST(folder: String, fileName: String, bearer: String) async throws -> FileItem? {
        let url = baseURL.appendingPathComponent("api/v1/filestorage/folder")
        struct Req: Codable { let path: String }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let pathValue = "/\(folder)/".replacingOccurrences(of: "//", with: "/")
        req.httpBody = try JSONEncoder().encode(Req(path: pathValue))

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw smError("Folder list (POST): invalid response") }
        guard (200...299).contains(http.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(FolderEnvelope.self, from: data)
        return decoded.folder?.files?.first(where: { ($0.fileName ?? "") == fileName })
    }

    /// POST /api/v1/filestorage/folder  with { "ownerEmailAddress": "...", "path": "/folder/" }
    private func fetchFileInfoPOSTWithOwner(folder: String, ownerEmail: String, fileName: String, bearer: String) async throws -> FileItem? {
        let url = baseURL.appendingPathComponent("api/v1/filestorage/folder")
        struct Req: Codable { let ownerEmailAddress: String; let path: String }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let pathValue = "/\(folder)/".replacingOccurrences(of: "//", with: "/")
        req.httpBody = try JSONEncoder().encode(Req(ownerEmailAddress: ownerEmail, path: pathValue))

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw smError("Folder list (POST+owner): invalid response") }
        guard (200...299).contains(http.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(FolderEnvelope.self, from: data)
        return decoded.folder?.files?.first(where: { ($0.fileName ?? "") == fileName })
    }

    // MARK: - Publish (/{id}/edit)
    private struct PublishHTTPError: Error {
        let status: Int
        let body: String
    }

    private func publishFile(ids: [String], shortLink: String?, bearer: String) async throws {
        var recoverableError: PublishHTTPError?
        for id in ids {
            do {
                try await performPublish(id: id, shortLink: shortLink, bearer: bearer)
                return
            } catch let error as PublishHTTPError {
                if error.status == 400 || error.status == 404 {
                    recoverableError = error
                    continue
                } else {
                    throw smError("Publish failed \(error.status): \(error.body)")
                }
            }
        }

        if let error = recoverableError {
            throw smError("Publish failed \(error.status): \(error.body)")
        }
        throw smError("Publish failed: no valid file identifiers were available.")
    }

    private func performPublish(id: String, shortLink: String?, bearer: String) async throws {
        struct EditReq: Codable {
            let published: Bool
            let shortLink: String?
        }
        var path = baseURL.path
        if !path.hasSuffix("/") {
            path.append("/")
        }
        path.append("api/v1/filestorage/")
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?")
        let encodedId = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
        path.append(encodedId)
        path.append("/edit")

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        guard let url = components?.url else { throw smError("Publish: invalid URL") }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(EditReq(published: true, shortLink: shortLink))

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw smError("Publish: invalid response") }
        guard (200...299).contains(http.statusCode) else {
            throw PublishHTTPError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Helpers
    private func sanitizeShortLink(from fileName: String) -> String {
        // Base = name without extension; strip spaces & odd chars
        let base = (fileName as NSString).deletingPathExtension
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let cleanedScalars = base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(cleanedScalars)
    }

    private func fallbackPublicURL(folder: String, file: String) -> String? {
        guard let host = publicBaseURL else { return nil }
        var comps = URLComponents(url: host.appendingPathComponent("FileStorage/Download"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            URLQueryItem(name: "folder", value: folder),
            URLQueryItem(name: "file", value: file)
        ]
        return comps?.url?.absoluteString
    }

    private func parseISO(_ s: String) -> Date? {
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso1.date(from: s) { return d }

        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        if let d = iso2.date(from: s) { return d }

        let fmts = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'"
        ]
        for f in fmts {
            let df = DateFormatter()
            df.calendar = Calendar(identifier: .gregorian)
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = f
            if let d = df.date(from: s) { return d }
        }
        return nil
    }

    private func smError(_ msg: String) -> NSError {
        NSError(domain: "SmarterMailService", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}

// MARK: - Data append helpers (for multipart)
private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
