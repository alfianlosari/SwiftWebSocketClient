//
//  WebSocketClient.swift
//
//  Created by Alfian Losari on 21/12/24.
//

import Foundation
import Network

@globalActor public actor WebSocketActor: GlobalActor {
    public static let shared = WebSocketActor()
}

public struct WebSocketConfiguration: Sendable {
    public var additionalHeaders: [String: String]
    public var pingInterval: TimeInterval
    public var pingTryReconnectCountLimit: Int
    
    public init(additionalHeaders: [String : String] = [:], pingInterval: TimeInterval = 5, pingTryReconnectCountLimit: Int = 2) {
        self.additionalHeaders = additionalHeaders
        self.pingInterval = pingInterval
        self.pingTryReconnectCountLimit = pingTryReconnectCountLimit
    }
}

public enum ConnectionState {
    case disconnected
    case connecting
    case connected
}

public typealias WebSocketClientMessage = URLSessionWebSocketTask.Message

@WebSocketActor
public class WebSocketClient: NSObject, Sendable {
    
    private let session: URLSession
    private let url: URL
    private let configuration: WebSocketConfiguration
    private var monitor: NWPathMonitor?
    
    private var wsTask: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?
    private var pingTryCount = 0
    
    public var onReceive: ((Result<WebSocketClientMessage, Error>) -> Void)?
    public var onConnectionStateChange: ((ConnectionState) -> Void)?
    
    private(set) var connectionState = ConnectionState.disconnected {
        didSet {
            onConnectionStateChange?(connectionState)
        }
    }
    
    public nonisolated init(url: URL, configuration: WebSocketConfiguration, session: URLSession = .init(configuration: .default)) {
        self.url = url
        self.configuration = configuration
        self.session = session
    }
    
    public func connect() {
        guard wsTask == nil else {
            print("WebSocket Task already exists")
            return
        }
        
        var request = URLRequest(url: url)
        configuration.additionalHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        wsTask = session.webSocketTask(with: request)
        wsTask?.delegate = self
        wsTask?.resume()
        connectionState = .connecting
        receiveMessage()
        startMonitorNetworkConnectivity()
        schedulePing()
    }
    
    public func send(_ message: WebSocketClientMessage) async throws {
        guard let task = wsTask, connectionState == .connected else {
            throw NSError(domain: "WebSocketClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "WebSocket is not connected."])
        }
        
        try await task.send(message)
    }
    
    public func disconnect() {
        disconnect(shouldRemoveNetworkMonitor: true)
    }
    
    private func receiveMessage() {
        wsTask?.receive { result in
            Task { @WebSocketActor [weak self] in
                guard let self else { return }
                self.onReceive?(result)
                self.receiveMessage()
            }
        }
    }
    
    private func startMonitorNetworkConnectivity() {
        guard monitor == nil else { return }
        monitor = .init()
        monitor?.pathUpdateHandler = { [weak self] path in
            Task { @WebSocketActor in
                guard let self = self else { return }
                print(path)
                
                if path.status == .satisfied, self.wsTask == nil {
                    self.connect()
                    return
                }
                
                if path.status != .satisfied {
                    self.disconnect(shouldRemoveNetworkMonitor: false)
                }
            }
        }
        monitor?.start(queue: .main)
    }
    
    private func schedulePing() {
        pingTask?.cancel()
        pingTryCount = 0
        pingTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(self?.configuration.pingInterval ?? 5))
                guard !Task.isCancelled, let self, let task = self.wsTask else { break }
                if task.state == .running, self.pingTryCount <
                    self.configuration.pingTryReconnectCountLimit {
                    self.pingTryCount += 1
                    print("Ping: Send")
                    task.sendPing { error in
                        if let error = error {
                            print("Ping: Failed: \(error.localizedDescription)")
                        } else {
                            print("Ping: Pong Received")
                            Task { @WebSocketActor [weak self]  in
                                self?.pingTryCount = 0
                            }
                        }
                    }
                } else {
                    self.reconnect()
                    break
                }
            }
        }
    }
    
    private func reconnect() {
        self.disconnect(shouldRemoveNetworkMonitor: false)
        self.connect()
    }
    
    private func disconnect(shouldRemoveNetworkMonitor: Bool) {
        self.wsTask?.cancel()
        self.wsTask = nil
        self.pingTask?.cancel()
        self.pingTask = nil
        self.connectionState = .disconnected
        if shouldRemoveNetworkMonitor {
            self.monitor?.cancel()
            self.monitor = nil
        }
    }
    
    deinit {
        self.wsTask?.cancel()
        self.pingTask?.cancel()
        self.monitor?.cancel()
    }
}

extension WebSocketClient: URLSessionWebSocketDelegate {
    
    nonisolated public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @WebSocketActor [weak self] in
            self?.connectionState = .connected
        }
    }
    
    nonisolated public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @WebSocketActor [weak self] in
            self?.connectionState = .disconnected
        }
    }
}


