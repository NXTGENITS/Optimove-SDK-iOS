//  Copyright © 2019 Optimove. All rights reserved.

import Foundation

import OptimoveCore

final class RealTime {

    private let configuration: RealtimeConfig
    private let realTimeQueue: DispatchQueue
    private let networking: RealTimeNetworking
    private let hanlder: RealTimeHanlder
    private var storage: OptimoveStorage
    private let eventBuilder: RealTimeEventBuilder
    private let coreEventFactory: CoreEventFactory

    // MARK: - Public

    required init(
        configuration: RealtimeConfig,
        storage: OptimoveStorage,
        networking: RealTimeNetworking,
        eventBuilder: RealTimeEventBuilder,
        handler: RealTimeHanlder,
        coreEventFactory: CoreEventFactory) {
        self.configuration = configuration
        self.storage = storage
        self.networking = networking
        self.realTimeQueue = DispatchQueue(
            label: "com.optimove.queue.realtime",
            qos: .utility
        )
        self.hanlder = handler
        self.eventBuilder = eventBuilder
        self.coreEventFactory = coreEventFactory
        performInitializationOperations()
        Logger.debug("RealTime initialized.")
    }

    func performInitializationOperations() {
        setFirstTimeVisitIfNeeded()
    }

    func report(event: OptimoveEvent, config: EventsConfig, retryFailedEvents: Bool = true) {
        guard config.supportedOnRealTime else {
            Logger.warn("Realtime: Event \(event.name) is not supported.")
            return
        }
        do {
            let context = createEventContext(event: event, config: config)
            try report(context: context, retryFailedEvents: retryFailedEvents)
        } catch {
            Logger.error(error.localizedDescription)
        }
    }

}

extension RealTime: EventableComponent {

    func handleEventable(_ context: EventableOperationContext) throws {
        guard !context.isBuffered else { return }
        switch context.operation {
        case .setUserId(userId: _):
            try reportUserId()
        case let .report(event: event):
            try reportEvent(event: event, retryFailedEvents: true)
        case let .reportScreenEvent(customURL: customURL, pageTitle: pageTitle, category: category):
            try reportEvent(
                event: try coreEventFactory.createEvent(
                    .pageVisit(screenPath: customURL,
                               screenTitle: pageTitle,
                               category: category
                    )
                )
            )
        case .dispatchNow:
            // Consciously do nothing.
            break
        }
    }

}

extension RealTime {

    func reportEvent(event: OptimoveEvent, retryFailedEvents: Bool = true) throws {
        let event = OptimoveEventDecoratorFactory.getEventDecorator(forEvent: event)
        let config = try obtainConfiguration(for: event)
        try OptimoveEventValidator.validate(event: event, withConfig: config)
        event.processEventConfig(config)
        report(event: event, config: config, retryFailedEvents: retryFailedEvents)
    }

    func reportUserId() throws {
        let event = try coreEventFactory.createEvent(.setUserId)
        try reportEvent(event: event, retryFailedEvents: false)
    }

    func reportUserEmail(_ email: String) throws {
        let event = SetUserEmailEvent(
            email: email
        )
        try reportEvent(event: event, retryFailedEvents: false)
    }

}

// MARK: - Private

private extension RealTime {

    func setFirstTimeVisitIfNeeded() {
        if storage[.firstVisitTimestamp] == nil {
            // Realtime server asked to get it in seconds
            storage[.firstVisitTimestamp] = Int64(Date().timeIntervalSince1970)
        }
    }

    // MARK: Transforming an event

    func obtainConfiguration(for event: OptimoveEvent) throws -> EventsConfig {
        guard let config = configuration.events[event.name] else {
            throw GuardError.custom("Configurations are missing for event \(event.name)")
        }
        return config
    }

    func createEventContext(event: OptimoveEvent, config: EventsConfig) -> RealTimeEventContext {
        switch event.name {
        case OptimoveKeys.Configuration.setUserId.rawValue:
            return RealTimeEventContext(
                event: event,
                config: config,
                type: .setUserID
            )
        case OptimoveKeys.Configuration.setEmail.rawValue:
            return RealTimeEventContext(
                event: event,
                config: config,
                type: .setUserEmail
            )
        default:
            return RealTimeEventContext(
                event: event,
                config: config,
                type: .regular
            )
        }
    }

    // MARK: Prepare before send a report

    func report(context: RealTimeEventContext, retryFailedEvents: Bool) throws {
        if retryFailedEvents {
            try retryUserDataIfNeeded(context: context)
        }
        sentReportEvent(context: context)
    }

    // MARK: Retry

    /// Verify that failed set_user_id is dispatched before failed set_email
    /// and before any custom event.
    /// This is requirment from the Server-side.
    func retryUserDataIfNeeded(context: RealTimeEventContext) throws {
        // Do not invoke retry on a new UserID
        if context.type != .setUserID {
            try retrySetUserIdEventIfNeeded()
        }
        // Do not invoke retry on a new UserEmail
        if context.type != .setUserEmail {
            try retrySetUserEmailIfNeeded()
        }
    }

    func retrySetUserIdEventIfNeeded() throws {
        if storage[.realtimeSetUserIdFailed] ?? false {
            try reportUserId()
        }
    }

    func retrySetUserEmailIfNeeded() throws {
        if storage[.realtimeSetEmailFailed] ?? false {
            try reportUserEmail(try cast(storage[.userEmail]))
        }
    }

    // MARK: Send report

    func sentReportEvent(context: RealTimeEventContext) {
        let realtimeToken = configuration.realtimeToken
        // The delay added as the temporary hotfix for the realtime race condition issue.
        // Should be removed right after release a solution on a server side.
        let delay: TimeInterval = 1
        realTimeQueue.asyncAfter(deadline: .now() + delay, execute: { [eventBuilder, networking, hanlder] in
            do {
                let realtimeEvent = try eventBuilder.createEvent(context: context, realtimeToken: realtimeToken)
                try networking.report(event: realtimeEvent) { (result) in
                    switch result {
                    case let .success(json):
                        hanlder.handleOnSuccess(context, json: json)
                    case let .failure(error):
                        hanlder.handleOnError(context, error: error)
                    }
                }
            } catch {
                hanlder.handleOnError(context, error: error)
            }
        })
    }

}

enum RealTimeError: LocalizedError {
    case eitherCustomerOrVisitorIdIsNil
    case deviceOffline

    var errorDescription: String? {
        switch self {
        case .eitherCustomerOrVisitorIdIsNil:
            return "Either a CustomerID or a VisitorID should not be nil."
        case .deviceOffline:
            return "Device is offline."
        }
    }
}
