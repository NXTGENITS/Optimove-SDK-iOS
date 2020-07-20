//  Copyright © 2019 Optimove. All rights reserved.

import Foundation
import OptimoveCore

class ComponentHandler: Node {
    private let commonComponents: [CommonComponent]
    private let optistreamComponents: [OptistreamComponent]
    private let optirstreamEventBuilder: OptistreamEventBuilder

    init(commonComponents: [CommonComponent],
         optistreamComponents: [OptistreamComponent],
         optirstreamEventBuilder: OptistreamEventBuilder
    ) {
        self.commonComponents = commonComponents
        self.optistreamComponents = optistreamComponents
        self.optirstreamEventBuilder = optirstreamEventBuilder
    }

    override func execute(_ operation: CommonOperation) throws {
        sendToCommonComponents(operation)
        sendToStreamComponents(operation)
    }

    private func sendToCommonComponents(_ operation: CommonOperation) {
        commonComponents.forEach { component in
            tryCatch {
                try component.handle(operation)
            }
        }
    }

    private func sendToStreamComponents(_ operation: CommonOperation) {
        switch operation {
        case .report(events: let events):
            let streamEvents: [OptistreamEvent] = events.compactMap { event in
                do {
                   return try optirstreamEventBuilder.build(event: event)
                } catch {
                    Logger.error(error.localizedDescription)
                    return nil
                }
            }
            optistreamComponents.forEach { (component) in
                tryCatch {
                    try component.handle(.report(events: streamEvents))
                }
            }
        case .dispatchNow:
            optistreamComponents.forEach { (component) in
                tryCatch {
                    try component.handle(.dispatchNow)
                }
            }
        default:
            break
        }
    }
}
