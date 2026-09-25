import Foundation
import Cocoa
import os

final class XPCHelperClient: NSObject {
    nonisolated static let shared = XPCHelperClient()
    
    private let serviceName = "com.apurvamukherjee.visor.VisorXPCHelper"
    private static let logger = Logger(subsystem: "com.apurvamukherjee.visor", category: "XPCHelperClient")
    
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?
    
    deinit {
        connection?.invalidate()
        stopMonitoringAccessibilityAuthorization()
    }
    
    // MARK: - Connection Management (Main Actor Isolated)
    
    @MainActor
    private func ensureConnection() -> NSXPCConnection {
        if let existing = connection {
            return existing
        }
        
        let conn = NSXPCConnection(serviceName: serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: XPCHelperProtocol.self)
        
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
            }
        }
        
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
            }
        }
        
        conn.resume()
        connection = conn
        return conn
    }

    // Visor: replaces AsyncXPCConnection, which this file used only for this.
    // The error handler fails the call if the helper dies before replying.
    private func withHelper<T>(
        _ body: @escaping (XPCHelperProtocol, CheckedContinuation<T, Error>) -> Void
    ) async throws -> T {
        let conn = await MainActor.run { ensureConnection() }
        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }
            guard let helper = proxy as? XPCHelperProtocol else {
                continuation.resume(throwing: XPCHelperClientError.unexpectedProxy)
                return
            }
            body(helper, continuation)
        }
    }
    
    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }

    // MARK: - Monitoring
    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        // Ensure only one monitor exists
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Call the helper method periodically which will notify on change
                _ = await self.isAccessibilityAuthorized()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // Expose whether the client is actively monitoring (useful for tests/debug)
    var isMonitoring: Bool {
        return monitoringTask != nil
    }
    
    // MARK: - Accessibility
    
    nonisolated func requestAccessibilityAuthorization() {
        Task {
            let conn = await MainActor.run { ensureConnection() }
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                Self.logger.error("Accessibility request failed: \(error.localizedDescription, privacy: .public)")
            }
            (proxy as? XPCHelperProtocol)?.requestAccessibilityAuthorization()
        }
    }
    
    nonisolated func isAccessibilityAuthorized() async -> Bool {
        do {
            let result: Bool = try await withHelper { service, continuation in
                service.isAccessibilityAuthorized { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        do {
            let result: Bool = try await withHelper { service, continuation in
                service.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    // MARK: - Keyboard Brightness
    
    nonisolated func currentKeyboardBrightness() async -> Float? {
        do {
            let result: NSNumber? = try await withHelper { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            return try await withHelper { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Screen Brightness
    
    nonisolated func currentScreenBrightness() async -> Float? {
        do {
            let result: NSNumber? = try await withHelper { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            return try await withHelper { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
}

enum XPCHelperClientError: Error {
    case unexpectedProxy
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}


