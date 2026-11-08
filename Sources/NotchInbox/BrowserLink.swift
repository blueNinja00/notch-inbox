import Foundation
import Network

/// Receives Gmail feeds and whole emails from the "Notch Inbox Link" browser add-on.
/// Listens on this Mac only (127.0.0.1) and accepts uploads only from that add-on.
/// Mail is never sent anywhere from here.
final class BrowserLink {
    /// Each minute's feeds, on the main thread. The answer tells the add-on which
    /// whole emails to fetch next.
    var onFeeds: (([AccountFeeds], FeedUpload) -> LinkReply)?
    /// One whole email (or why it couldn't be fetched), on the main thread.
    var onEmail: ((EmailUpload) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "NotchInbox.BrowserLink")
    /// Different every time the app starts, so the add-on can tell it restarted (after an
    /// update, say) and sync straight away.
    private static let launchID = UUID().uuidString

    /// Whether the add-on can reach the app, and if not why, for Copy Debug Info.
    private(set) var status = "starting"

    /// Starts listening (on the main thread). If the port is taken, say by an older copy of
    /// the app that's still quitting, it keeps trying every few seconds.
    func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: LinkAddOn.port) else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredInterfaceType = .loopback
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.serve(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    self?.listenerChanged(state)
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            status = "couldn't listen: \(error.localizedDescription)"
            NSLog("Notch Inbox: couldn't open the browser link: \(error.localizedDescription)")
            restartSoon()
        }
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            status = "listening on 127.0.0.1:\(LinkAddOn.port)"
        case .failed(let error), .waiting(let error):
            status = "not listening: \(error.localizedDescription)"
            NSLog("Notch Inbox: browser link stopped (\(error.localizedDescription)); trying again")
            restartSoon()
        default:
            break
        }
    }

    private func restartSoon() {
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.start()
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data = data {
                buffer.append(data)
            }
            if buffer.count > HTTPRequest.maxSize + 64 * 1024 {
                BrowserLink.reply(connection, status: 413)
                return
            }
            switch HTTPRequest.parse(buffer) {
            case .complete(let request):
                self.handle(request, on: connection)
            case .invalid:
                BrowserLink.reply(connection, status: 400)
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.read(connection, buffer: buffer)
                }
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        if request.method == "OPTIONS" {
            BrowserLink.reply(connection, status: 204)
            return
        }
        guard request.method == "POST", request.path == "/feeds" || request.path == "/message" else {
            BrowserLink.reply(connection, status: 404)
            return
        }
        guard LinkAddOn.accepts(request) else {
            BrowserLink.reply(connection, status: 403)
            return
        }

        if request.path == "/message" {
            guard let email = try? JSONDecoder().decode(EmailUpload.self, from: request.body) else {
                BrowserLink.reply(connection, status: 400)
                return
            }
            BrowserLink.reply(connection, status: 200)
            DispatchQueue.main.async { [weak self] in
                self?.onEmail?(email)
            }
            return
        }

        guard let upload = try? JSONDecoder().decode(FeedUpload.self, from: request.body) else {
            BrowserLink.reply(connection, status: 400)
            return
        }
        let feeds = upload.feeds.compactMap { $0.parsed() }
        DispatchQueue.main.async { [weak self] in
            let answer = self?.onFeeds?(feeds, upload) ?? LinkReply()
            let json = (try? JSONEncoder().encode(answer)) ?? Data("{}".utf8)
            BrowserLink.reply(connection, status: 200, json: json)
        }
    }

    private static func reply(_ connection: NWConnection, status: Int, json: Data? = nil) {
        var head = "HTTP/1.1 \(status) \(HTTPRequest.reason(for: status))\r\n"
        if json != nil {
            head += "Content-Type: application/json\r\n"
        }
        head += "Content-Length: \(json?.count ?? 0)\r\n"
            + "Access-Control-Allow-Origin: chrome-extension://\(LinkAddOn.id)\r\n"
            + "Access-Control-Allow-Methods: POST, OPTIONS\r\n"
            + "Access-Control-Allow-Headers: Content-Type\r\n"
            + "Access-Control-Allow-Private-Network: true\r\n"
            + "Access-Control-Expose-Headers: X-Notch-Launch\r\n"
            + "X-Notch-Launch: \(launchID)\r\n"
            + "Connection: close\r\n\r\n"
        var message = Data(head.utf8)
        if let json = json {
            message.append(json)
        }
        connection.send(content: message, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
