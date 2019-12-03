//  Copyright © 2019 Optimove. All rights reserved.

import XCTest
@testable import OptimoveCore

class ConfigurationBuilderTests: XCTestCase {

    func test_build_configuration() {
        let tenantConfig = TenantConfigFixture().build()
        let globalConfig = GlobalConfigFixture().build()

        let builder = ConfigurationBuilder(globalConfig: globalConfig, tenantConfig: tenantConfig)
        let configuration = builder.build()

        XCTAssert(configuration.tenantID == tenantConfig.optitrack.siteId)
        XCTAssert(configuration.logger.logServiceEndpoint == globalConfig.general.logsServiceEndpoint)
        XCTAssert(configuration.realtime.realtimeToken == tenantConfig.realtime.realtimeToken)
        XCTAssert(configuration.optitrack.eventCategoryName == globalConfig.optitrack.eventCategoryName)
    }

}
