//  Copyright © 2017 Optimove. All rights reserved.

import Foundation
import OptimoveCore

final class OptimoveSDKInitializer {

    private let deviceStateMonitor: OptimoveDeviceStateMonitor
    private let storage: OptimoveStorage
    private let networking: RemoteConfigurationNetworking
    private let configurationRepository: ConfigurationRepository
    private let componentFactory: ComponentFactory
    private let components: MutableComponentsPool
    private let handlersPool: HandlersPool

    private lazy var operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    // MARK: - Construction

    init(deviceStateMonitor: OptimoveDeviceStateMonitor,
         storage: OptimoveStorage,
         networking: RemoteConfigurationNetworking,
         configurationRepository: ConfigurationRepository,
         componentFactory: ComponentFactory,
         componentsPool: MutableComponentsPool,
         handlersPool: HandlersPool) {
        self.deviceStateMonitor = deviceStateMonitor
        self.storage = storage
        self.networking = networking
        self.configurationRepository = configurationRepository
        self.componentFactory = componentFactory
        self.components = componentsPool
        self.handlersPool = handlersPool
    }

    // MARK: - API

    func initializeFromRemoteServer(completion: @escaping ResultBlockWithBool) {
        Logger.info("Start initializtion from remote configurations.")
        handleFetchConfigurationFromRemote(completion: completion)
    }

    /// When the SDK is initialized by a push notification start the initialization from the local JSON file.
    func initializeFromLocalConfigs(completion: @escaping ResultBlockWithBool) {
        Logger.info("Start initializtion from local configurations.")
        handleFetchConfigurationFromLocal(didComplete: completion)
    }

}

private extension OptimoveSDKInitializer {

    func handleFetchConfigurationFromRemote(completion: @escaping ResultBlockWithBool) {
        // Operations that execute asynchronously to fetch remote configs.
        let downloadOperations: [Operation] = [
            GlobalConfigurationDownloader(
                networking: networking,
                repository: configurationRepository
            ),
            TenantConfigurationDownloader(
                networking: networking,
                repository: configurationRepository
            )
        ]

        // Operation merge all remote configs to a invariant.
        let mergeOperation = MergeRemoteConfigurationOperation(
            repository: configurationRepository
        )

        // Set the merge operation as dependent on the download operations.
        downloadOperations.forEach {
            mergeOperation.addDependency($0)
        }

        // Set the completion operation for aline two asynchronous operations together.
        let completionOperation = BlockOperation {
            do {
                let configuration = try self.configurationRepository.getConfiguration()
                self.initialize(configuration, completion: completion)
            } catch {
                Logger.error(error.localizedDescription)
                completion(false)
            }
        }

        // Combine the operations for an executing
        let operations = downloadOperations + [mergeOperation]
        operations.forEach {
            // Set the completion operation as dependent for all operations before they start executing.
            completionOperation.addDependency($0)
            operationQueue.addOperation($0)
        }
        // The completion operation is performing on the current queue.
        operationQueue.addOperation(completionOperation)
    }

    func handleFetchConfigurationFromLocal(didComplete: @escaping ResultBlockWithBool) {
        do {
            let configuration = try configurationRepository.getConfiguration()
            Logger.debug("Setup components from local configuration file.")
            initialize(configuration, completion: didComplete)
        } catch {
            Logger.error(
                "Local configuration file could not be parsed. Reason: \(error.localizedDescription)"
            )
            didComplete(false)
        }
    }

    func initialize(_ configuration: Configuration, completion: @escaping ResultBlockWithBool) {
        updateEnvironment(configuration)
        setupOptimoveComponents(from: configuration, completion: completion)
    }

    func setupOptimoveComponents(from configuration: Configuration, completion: @escaping ResultBlockWithBool) {
        guard RunningFlagsIndication.isSdkNeedInitializing() else {
            Logger.debug("SDK already running, skip initialization before lock.")
            completion(false)
            return
        }
        RunningFlagsIndication.isInitializerRunning = true
        components.addComponent(componentFactory.createOptitrackComponent(configuration: configuration))
        components.addComponent(componentFactory.createRealtimeComponent(configuration: configuration))
        handlersPool.addNextEventableHandler(ComponentEventableHandler(component: components))
        components.addComponent(componentFactory.createOptipushComponent(configuration: configuration))
        handlersPool.addNextPushableHandler(ComponentPushableHandler(component: components))
        Logger.info("All components setup finished.")
        completion(true)
    }

}

extension OptimoveSDKInitializer {


    func updateEnvironment(_ config: Configuration) {
        updateLoggerStreamContainers(config)
        storage.set(value: config.tenantID, key: .siteID)
    }

    func updateLoggerStreamContainers(_ config: Configuration) {
        MultiplexLoggerStream.mutateStreams { logger in
            logger.tenantId = config.tenantID
            logger.endpoint = config.logger.logServiceEndpoint
        }
    }
}
