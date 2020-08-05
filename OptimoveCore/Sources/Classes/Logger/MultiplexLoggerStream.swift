//  Copyright © 2019 Optimove. All rights reserved.

import Foundation

public final class MultiplexLoggerStream {

    private struct Constants {
        static let delimiter = "/"
        static let placeholder = ""
    }

    static var streams: [LoggerStream] = []

    private static let queue = DispatchQueue(label: "com.optimove.sdk.logger", qos: .background)

    public static func log(
        level: LogLevelCore,
        fileName: String?,
        methodName: String?,
        logModule: String?,
        _ message: String
    ) {
        queue.async {

            let file = fileName?.components(separatedBy: Constants.delimiter).last ?? Constants.placeholder
            let function = methodName ?? Constants.placeholder

            streams.forEach { stream in

                switch stream.policy {

                case .custom(let filterFunction):
                    if filterFunction(level)  {
                        fallthrough
                    }

                case .all:
                    stream.log(
                        level: level,
                        fileName: file,
                        methodName: function,
                        logModule: logModule,
                        message: message
                    )
                }
            }
        }
    }

    public static func add(stream: LoggerStream) {
        queue.async {
            streams.append(stream)
        }
    }

    public static func mutateStreams(mutator: @escaping (MutableLoggerStream) -> Void) {
        queue.async {
            streams
                .compactMap { $0 as? MutableLoggerStream }
                .forEach (mutator)
        }
    }
}
