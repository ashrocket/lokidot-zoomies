import Foundation
import Darwin
import ZoomiesCore

/// Delegate callbacks run on one serial queue. No credentials, cookies or shared cache.
final class UpdateTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Output { case metadata(Data), package(URL, UpdateRelease) }
    private let release: UpdateRelease?
    private let completion: (Result<Output, Error>) -> Void
    private var session: URLSession!
    private var data = Data()
    private var verifier: UpdateIntegrityVerifier?
    private var file: FileHandle?
    private var staging: URL?
    private var destination: URL?
    private var failure: Error?
    private var redirectCount = 0
    private var finished = false

    init(release: UpdateRelease? = nil, completion: @escaping (Result<Output, Error>) -> Void) throws {
        self.release = release
        self.completion = completion
        super.init()
        if let release {
            var template = Array(URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("LokiDot-update.XXXXXX").path.utf8CString)
            guard let path = mkdtemp(&template) else { throw UpdateError("Cannot create a private update folder.") }
            let directory = URL(fileURLWithPath: String(cString: path), isDirectory: true)
            staging = directory
            let url = directory.appendingPathComponent(release.filename)
            let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else {
                try? FileManager.default.removeItem(at: directory)
                throw UpdateError("Cannot create the installer download.")
            }
            destination = url
            file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            verifier = UpdateIntegrityVerifier(release: release)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = release == nil ? 30 : 300
        configuration.waitsForConnectivity = false
        let queue = OperationQueue()
        queue.name = "LokiDot update transfer"
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    func start() {
        var request = URLRequest(url: release?.downloadURL ?? UpdateRelease.metadataURL)
        request.setValue("LokiDot-Zoomies-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue(release == nil ? "application/vnd.github+json" : "application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if release == nil { request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version") }
        session.dataTask(with: request).resume()
    }

    func cancel() { session.invalidateAndCancel() }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirectCount += 1
        // Metadata has one fixed endpoint and accepts no redirects, even within GitHub.
        guard release != nil, redirectCount <= 5, let url = request.url,
              UpdateRelease.allowsAssetRedirect(to: url) else {
            failure = UpdateError("GitHub redirected the update to an unexpected location.")
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Never prompt for or supply account credentials, including task-level HTTP auth.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard failure == nil, let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            failure = failure ?? UpdateError("GitHub could not provide the update. Try again later.")
            completionHandler(.cancel); return
        }
        let limit = release?.size ?? UpdateRelease.maximumMetadataBytes
        guard response.expectedContentLength <= Int64(limit),
              release == nil || response.expectedContentLength < 0 || response.expectedContentLength == Int64(limit) else {
            failure = UpdateError("The update response has an unexpected size.")
            completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard failure == nil else { return }
        do {
            if verifier != nil {
                try verifier?.append(chunk)
                try file?.write(contentsOf: chunk)
            } else {
                guard chunk.count <= UpdateRelease.maximumMetadataBytes - data.count else {
                    throw UpdateError("The release response is too large.")
                }
                data.append(chunk)
            }
        } catch { failure = error; dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        finished = true
        let result: Result<Output, Error>
        do {
            if let error = failure ?? error { throw error }
            if let destination, let verifier, let release {
                try verifier.finish()
                try file?.synchronize()
                try file?.close()
                file = nil
                // Preserve the normal downloaded-file security boundary for URLSession writes.
                let quarantine = "0083;\(String(Int(Date().timeIntervalSince1970), radix: 16));LokiDot Zoomies;\(UUID().uuidString)"
                let written = quarantine.withCString { bytes in
                    setxattr(destination.path, "com.apple.quarantine", bytes, strlen(bytes), 0, 0)
                }
                guard written == 0 else { throw UpdateError("Cannot apply macOS download security information. The installer will not be opened.") }
                result = .success(.package(destination, release))
            } else { result = .success(.metadata(data)) }
        } catch {
            try? file?.close(); file = nil
            // Only this transfer's private, generated scratch directory is removed.
            if let staging { try? FileManager.default.removeItem(at: staging) }
            result = .failure(error)
        }
        session.finishTasksAndInvalidate()
        completion(result)
    }

    /// Re-read the actual staged file before handoff, not only the network stream.
    /// This excludes links and other-user files, but cannot exclude arbitrary same-user mutation.
    static func verifyStagedPackage(at url: URL, release: UpdateRelease) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw UpdateError("The verified installer is no longer available.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_uid == geteuid(), before.st_nlink == 1,
              (before.st_mode & 0o077) == 0, before.st_size == release.size else {
            throw UpdateError("The staged installer has unexpected ownership, permissions, type, or size.")
        }
        var verifier = UpdateIntegrityVerifier(release: release)
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty { try verifier.append(chunk) }
        try verifier.finish()
        var after = stat(), pathState = stat()
        guard fstat(descriptor, &after) == 0, lstat(url.path, &pathState) == 0,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              after.st_dev == pathState.st_dev, after.st_ino == pathState.st_ino,
              (pathState.st_mode & S_IFMT) == S_IFREG,
              fgetxattr(descriptor, "com.apple.quarantine", nil, 0, 0, 0) > 0 else {
            throw UpdateError("The staged installer changed during verification. It will not be opened.")
        }
    }
}
