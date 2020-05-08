//  Copyright © 2019 Optimove. All rights reserved.

protocol CommonComponent {
    func handle(_: Operation) throws
}

enum OptistreamComponentType {
    case realtime
    case track
}

protocol OptistreamComponent {
    var componentType: OptistreamComponentType { get }
    func handle(_: OptistreamOperation) throws
}
