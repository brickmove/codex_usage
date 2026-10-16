import Foundation
import Darwin

public struct CodexClient: Sendable {
    public var executablePath: String
    public var codexHome: String
    public var timeout: TimeInterval
    public init(executablePath: String = "", codexHome: String = "", timeout: TimeInterval = 30) {
        self.executablePath = executablePath; self.codexHome = codexHome; self.timeout = timeout
    }
    public static func locateExecutable(configured: String = "") throws -> String {
        let fm = FileManager.default
        if !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let path = AppSettings.expandedPath(configured)
            guard fm.isExecutableFile(atPath: path) else { throw UsageError.message("设置中的 Codex 路径不可执行，请选择 codex 文件。") }
            return path
        }
        let folders = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/Applications/Codex.app/Contents/Resources"]
        for folder in folders {
            let path = AppSettings.expandedPath(folder) + "/codex"
            if fm.isExecutableFile(atPath: path) { return path }
        }
        throw UsageError.message("未找到 Codex CLI，请安装并登录 Codex，或在设置中指定路径。")
    }
    public func readQuota(onAccount: (@Sendable (CodexAccount?) -> Void)? = nil) throws -> QuotaSnapshot {
        let path = try Self.locateExecutable(configured: executablePath)
        let session = try RPCSession(path: path, codexHome: codexHome, timeout: timeout)
        defer { session.close() }
        _ = try session.call(id: 1, method: "initialize", params: [
            "clientInfo": ["name": "codex_usage", "title": "Codex Usage", "version": "0.3.3"],
            "capabilities": ["experimentalApi": true]
        ])
        try session.send(["method": "initialized"])
        let accountData = try session.call(id: 2, method: "account/read", params: ["refreshToken": false])
        let accountResult = try JSONDecoder().decode(AccountResult.self, from: accountData)
        onAccount?(accountResult.account)
        guard let account = accountResult.account else {
            throw UsageError.message("Codex 尚未登录，请先运行 codex login，然后刷新。")
        }
        guard account.type == "chatgpt" else {
            throw UsageError.message("当前 Codex 使用 API Key 或其他认证方式，无法查询 ChatGPT 订阅额度。本地统计仍可用。")
        }
        let data = try session.call(id: 3, method: "account/rateLimits/read", params: [:])
        let limits: RateLimitsResponse
        do { limits = try JSONDecoder().decode(RateLimitsResponse.self, from: data) }
        catch { throw UsageError.message("无法解析 Codex 额度响应，请检查 Codex CLI 版本。") }
        guard limits.bucket != nil else { throw UsageError.message("服务未返回 Codex 额度，请稍后重试。") }
        return QuotaSnapshot(response: limits, email: account.email, account: account)
    }
}

private struct AccountResult: Decodable {
    var account: CodexAccount?
}

/// Each refresh owns a short-lived stdio session. No model turn, login, or reset is invoked.
private final class RPCSession {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let deadline: Date
    private var buffer = Data()
    private var closed = false
    private var launched = false

    init(path: String, codexHome: String, timeout: TimeInterval) throws {
        deadline = Date().addingTimeInterval(timeout)
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server", "-c", "analytics.enabled=false"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (environment["PATH"] ?? "/usr/bin:/bin") + ":/opt/homebrew/bin:/usr/local/bin:" + AppSettings.expandedPath("~/.local/bin")
        if !codexHome.isEmpty { environment["CODEX_HOME"] = AppSettings.expandedPath(codexHome) }
        process.environment = environment
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run(); launched = true }
        catch { throw UsageError.message("无法启动 Codex CLI：\(error.localizedDescription)") }
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
    }
    deinit { close() }
    func close() {
        guard !closed else { return }; closed = true
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
        guard launched else { return }
        if process.isRunning {
            process.terminate()
            let end = Date().addingTimeInterval(0.4)
            while process.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
    }
    func send(_ message: [String: Any]) throws {
        guard process.isRunning else { throw UsageError.message("Codex App Server 已退出，请检查 Codex 配置。") }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        do { try input.fileHandleForWriting.write(contentsOf: data) }
        catch { throw UsageError.message("无法与 Codex App Server 通信，请重试。") }
    }
    func call(id: Int, method: String, params: [String: Any]) throws -> Data {
        try send(["id": id, "method": method, "params": params])
        while true {
            let line = try readLine()
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if message["method"] != nil {
                if let requestID = message["id"] {
                    try send(["id": requestID, "error": ["code": -32601, "message": "Unsupported client request"]])
                }
                continue
            }
            guard (message["id"] as? Int) == id else { continue }
            if let error = message["error"] as? [String: Any] {
                let code = error["code"] as? Int ?? 0
                // Avoid reflecting arbitrary server payloads or credentials into logs/UI.
                if code == -32601 { throw UsageError.message("Codex CLI 不支持所需接口，请更新 Codex。") }
                throw UsageError.message("Codex 额度查询失败（RPC \(code)），请确认已登录且网络可用，然后重试。")
            }
            guard let result = message["result"], !(result is NSNull) else {
                throw UsageError.message("Codex 返回了空响应，请稍后重试。")
            }
            return try JSONSerialization.data(withJSONObject: result)
        }
    }
    private func readLine() throws -> Data {
        while true {
            if let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline); return line
            }
            if Task<Never, Never>.isCancelled { throw CancellationError() }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw UsageError.message("Codex 额度查询超时，请检查网络后刷新。本地统计不受影响。") }
            var fd = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let result = poll(&fd, 1, Int32(min(remaining * 1000, 250)))
            if result < 0 {
                if errno == EINTR { continue }
                throw UsageError.message("读取 Codex 响应失败。")
            }
            if result == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 32768)
            let count = Darwin.read(fd.fd, &bytes, bytes.count)
            guard count > 0 else { throw UsageError.message("Codex App Server 提前退出，请检查 CLI 配置后重试。") }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 4 * 1024 * 1024 else { throw UsageError.message("Codex 响应超出大小限制。") }
        }
    }
}
