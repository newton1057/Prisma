import Foundation
import Network

struct SpeakRequest: Codable {
    var text: String
    var cwd: String?
    var session_id: String?
    var source: String?
    var engine: String?
    var voice: String?
}

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<headerEnd.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        var lines = headerString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }

        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }

        let method = String(requestLine[0])
        let path = String(requestLine[1])

        var headers: [String: String] = [:]
        for line in lines {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}

final class HTTPServer {
    private let candidatePorts: [UInt16]
    private let token: String
    private let onSpeak: (SpeakRequest) -> Void
    private let onStop: () -> Void

    private let queue = DispatchQueue(label: "Prisma.HTTPServer")
    private var listener: NWListener?
    private var portIndex = 0
    private(set) var isRunning = false
    private(set) var boundPort: Int = 0

    var onStateChange: ((Bool, String) -> Void)?

    init(
        port: Int,
        token: String,
        onSpeak: @escaping (SpeakRequest) -> Void,
        onStop: @escaping () -> Void
    ) {
        let base = UInt16(clamping: port)
        self.candidatePorts = (0..<12).compactMap { offset in
            let value = Int(base) + offset
            return value <= 65535 ? UInt16(value) : nil
        }
        self.token = token
        self.onSpeak = onSpeak
        self.onStop = onStop
    }

    func start() {
        portIndex = 0
        bindCurrentPort()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        boundPort = 0
    }

    private func bindCurrentPort() {
        guard portIndex < candidatePorts.count else {
            DispatchQueue.main.async {
                self.onStateChange?(false, "No hay puertos libres para Prisma")
            }
            return
        }

        let port = candidatePorts[portIndex]
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            portIndex += 1
            bindCurrentPort()
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: endpointPort
            )

            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                    self.boundPort = Int(port)
                    DispatchQueue.main.async {
                        self.onStateChange?(true, "Escuchando en 127.0.0.1:\(port)")
                    }
                case .failed(let error):
                    self.isRunning = false
                    self.listener?.cancel()
                    self.listener = nil
                    self.portIndex += 1
                    if self.portIndex < self.candidatePorts.count {
                        self.bindCurrentPort()
                    } else {
                        DispatchQueue.main.async {
                            self.onStateChange?(false, "No se pudo abrir ningún puerto: \(error.localizedDescription)")
                        }
                    }
                case .cancelled:
                    self.isRunning = false
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            portIndex += 1
            bindCurrentPort()
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var accumulated = buffer
            if let data { accumulated.append(data) }

            if let request = HTTPRequest.parse(accumulated) {
                self.route(request, on: connection)
            } else if isComplete || error != nil || accumulated.count > 1_000_000 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: accumulated)
            }
        }
    }

    private func route(_ request: HTTPRequest, on connection: NWConnection) {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path

        if request.method == "GET" && path == "/health" {
            respond(connection, status: 200, json: [
                "ok": true,
                "app": "Prisma",
                "version": "1.0"
            ])
            return
        }

        guard isAuthorized(request) else {
            respond(connection, status: 401, json: ["ok": false, "error": "unauthorized"])
            return
        }

        switch (request.method, path) {
        case ("POST", "/speak"):
            guard let body = request.body,
                  let speak = try? JSONDecoder().decode(SpeakRequest.self, from: body),
                  !speak.text.isEmpty else {
                respond(connection, status: 400, json: ["ok": false, "error": "invalid body"])
                return
            }
            DispatchQueue.main.async { self.onSpeak(speak) }
            respond(connection, status: 200, json: ["ok": true])

        case ("POST", "/stop"):
            DispatchQueue.main.async { self.onStop() }
            respond(connection, status: 200, json: ["ok": true])

        default:
            respond(connection, status: 404, json: ["ok": false, "error": "not found"])
        }
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        if request.headers["x-prisma-token"] == token { return true }
        if request.headers["x-codexvoz-token"] == token { return true }
        if request.headers["authorization"] == "Bearer \(token)" { return true }
        return false
    }

    private func respond(_ connection: NWConnection, status: Int, json: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        default: reason = "Error"
        }

        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
