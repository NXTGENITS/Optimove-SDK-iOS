//  Copyright © 2019 Optimove. All rights reserved.

protocol CommonComponent {
    func handle(_: CommonOperation) throws
}

protocol OptistreamComponent {
    func handle(_: OptistreamOperation) throws
}