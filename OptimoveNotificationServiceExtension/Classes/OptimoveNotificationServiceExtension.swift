import Foundation
import UserNotifications
import os.log
import OptimoveCore

@objc public class OptimoveNotificationServiceExtension: NSObject {

    @objc public private(set) var isHandledByOptimove: Bool = false
    
    private let bundleIdentifier: String
    private let operationQueue: OperationQueue

    private var bestAttemptContent: UNMutableNotificationContent?
    private var contentHandler: ((UNNotificationContent) -> Void)?

    @objc public init(appBundleId: String) {
        bundleIdentifier = appBundleId

        operationQueue = OperationQueue()
        operationQueue.qualityOfService = .userInitiated
    }
    
    @objc public convenience override init() {
        guard let bundleIdentifier = Bundle.extractHostAppBundle()?.bundleIdentifier else {
            fatalError("Unable to find a bundle identifier.")
        }
        self.init(appBundleId: bundleIdentifier)
    }


    /// The method verified that a request belong to Optimove channel. The Oprimove request might be modified.
    ///
    /// - Parameters:
    ///   - request: The original notification request.
    ///   - contentHandler: A UNNotificationContent object with the content to be displayed to the user.
    /// - Returns: Returns `true` if the message was consumed by Optimove, otherwise this request is not  from Optimove.
    @objc public func didReceive(_ request: UNNotificationRequest,
                                 withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) -> Bool {
        let payload: NotificationPayload
        let groupedUserDefaults: UserDefaults
        let sharedUserDefaults: UserDefaults
        let fileStorage: FileStorage
        do {
            groupedUserDefaults = try UserDefaults.grouped(tenantBundleIdentifier: bundleIdentifier)
            sharedUserDefaults = try UserDefaults.shared(tenantBundleIdentifier: bundleIdentifier)
            fileStorage = try FileStorageImpl(bundleIdentifier: bundleIdentifier, fileManager: .default)
            payload = try extractNotificationPayload(request)
            bestAttemptContent = try unwrap(createBestAttemptBaseContent(request: request, payload: payload))
        } catch {
            contentHandler(request.content)
            return false
        }
        isHandledByOptimove = true
        self.contentHandler = contentHandler

        let storage = StorageFacade(
            groupedStorage: groupedUserDefaults,
            sharedStorage: sharedUserDefaults,
            fileStorage: fileStorage
        )
        let configurationRepository = ConfigurationRepositoryImpl(storage: storage)
        let operationsToExecute: [Operation] = [
            NotificationDeliveryReporter(
                repository: configurationRepository,
                bundleIdentifier: bundleIdentifier,
                storage: storage,
                notificationPayload: payload
            ),
            // TODO: Deeplink Extracter move to main app.
            MediaAttachmentDownloader(
                notificationPayload: payload,
                bestAttemptContent: bestAttemptContent!
            )
        ]
        // The completion operation going to be executed right after all operations are finished.
        let completionOperation = BlockOperation {
            os_log("Operations were completed", log: OSLog.notification, type: .info)
            contentHandler(self.bestAttemptContent!)
        }
        os_log("Operations were scheduled", log: OSLog.notification, type: .info)
        operationsToExecute.forEach {
            // Set the completion operation as dependent for all operations before they start executing.
            completionOperation.addDependency($0)
            operationQueue.addOperation($0)
        }
        // The completion operation is performing on the main queue.
        OperationQueue.main.addOperation(completionOperation)
        return true
    }

    /// The method called by system in case if `didReceive(_:withContentHandler:)` takes to long to execute or
    /// out of memory.
    @objc public func serviceExtensionTimeWillExpire() {
        if let bestAttemptContent = bestAttemptContent {
            contentHandler?(bestAttemptContent)
        }
    }
}

private extension OptimoveNotificationServiceExtension {
    
    func extractNotificationPayload(_ request: UNNotificationRequest) throws -> NotificationPayload {
        let userInfo = request.content.userInfo
        let data = try JSONSerialization.data(withJSONObject: userInfo)
        let decoder = JSONDecoder()
        return try decoder.decode(NotificationPayload.self, from: data)
    }
    
    func createBestAttemptBaseContent(request: UNNotificationRequest,
                                      payload: NotificationPayload) -> UNMutableNotificationContent? {
        guard let bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent else {
            os_log("Unable to copy content.", log: OSLog.notification, type: .fault)
            return nil
        }
        bestAttemptContent.title = payload.title
        bestAttemptContent.body = payload.content
        return bestAttemptContent
    }
}

extension OSLog {
    static var subsystem = Bundle.main.bundleIdentifier!
    static let notification = OSLog(subsystem: subsystem, category: "notification")
}
