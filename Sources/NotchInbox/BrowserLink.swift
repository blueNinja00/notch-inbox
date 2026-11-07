import Foundation
import Network

/// Receives Gmail feeds from the "Notch Inbox Link" browser add-on.
/// Listens on this Mac only (127.0.0.1) and accepts uploads only from that add-on.
/// Mail is never sent anywhere from here.
final class BrowserLink {
    var onFeeds: (([GmailFeed]) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "NotchInbox.BrowserLink")

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
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("Notch Inbox: couldn't open the browser link: \(error.localizedDescription)")
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data = data {
                buffer.append(data)
            }
            if buffer.count > HTTPRequest.maxSize {
                self.reply(connection, status: 413)
                return
            }
            switch HTTPRequest.parse(buffer) {
            case .complete(let request):
                self.handle(request, on: connection)
            case .invalid:
                self.reply(connection, status: 400)
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
            reply(connection, status: 204)
            return
        }
        guard request.method == "POST", request.path == "/feeds" else {
            reply(connection, status: 404)
            return
        }
        guard LinkAddOn.accepts(request) else {
            reply(connection, status: 403)
            return
        }
        guard let upload = try? JSONDecoder().decode(FeedUpload.self, from: request.body) else {
            reply(connection, status: 400)
            return
        }

        let feeds = upload.feeds.compactMap { GmailFeedParser.parse(Data($0.xml.utf8)) }
        reply(connection, status: 200)
        DispatchQueue.main.async { [weak self] in
            self?.onFeeds?(feeds)
        }
    }

    private func reply(_ connection: NWConnection, status: Int) {
        let head = "HTTP/1.1 \(status) \(HTTPRequest.reason(for: status))\r\n"
            + "Content-Length: 0\r\n"
            + "Access-Control-Allow-Origin: chrome-extension://\(LinkAddOn.id)\r\n"
            + "Access-Control-Allow-Methods: POST, OPTIONS\r\n"
            + "Access-Control-Allow-Headers: Content-Type\r\n"
            + "Access-Control-Allow-Private-Network: true\r\n"
            + "Connection: close\r\n\r\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
