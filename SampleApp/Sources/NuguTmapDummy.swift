//
//  NuguTmapDummy.swift
//  SampleApp
//
//  Created by childc on 2021/02/26.
//  Copyright © 2021 sktelecom. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

import NuguCore
import NuguAgents

public class NuguTmapDummy {
    public lazy var contextInfoProvider: ContextInfoProviderType = { [weak self] completion in
        guard let self = self else { return }
        
        var payload = [String: AnyHashable?]()
        payload["version"] = "1.0"
        
        let currentPoi: [String: AnyHashable?] = [
            "latitude": 37.5662956237793,
            "longitude": 126.98905944824219,
            "centerY": 1352286,
            "centerX": 4571682,
            "address": "서울특별시 중구 을지로"
        ]
        
        let toPoi: [String: AnyHashable?] = [
            "latitude": 556586486812705,
            "longitude": 126.97569056145043,
            "centerY": 1351941,
            "centerX": 4571208,
            "name": "SK남산빌딩",
            "address": "서울특별시 중구 퇴계로"
        ]
        
        let route: [String: AnyHashable?] = [
            "status": "ROUTING",
            "current": [
                "poi": currentPoi
            ],
            "to": [
                "distanceLeftInMeter": 2661 as AnyHashable,
                "timeLeftInsec": 613 as AnyHashable,
                "poi": toPoi
            ]
        ]
        
        payload["route"] = route
        
        completion(
            ContextInfo(
                contextType: .capability,
                name: "NuguTmap",
                payload: payload.compactMapValues { $0 }
            )
        )
    }
    
    public init(contextManager: ContextManageable) {
        contextManager.addProvider(contextInfoProvider)
    }
}

