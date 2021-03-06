//
//  AudioPlayerState.swift
//  NuguAgents
//
//  Created by MinChul Lee on 22/04/2019.
//  Copyright (c) 2019 SK Telecom Co., Ltd. All rights reserved.
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

/// Identifies the player state.
public enum AudioPlayerState {
    /// Initial state, prior to acting on the first Play directive.
    case idle
    /// Indicates that audio is currently playing.
    case playing
    /// Indicates that audio playback was stopped due to an error or a directive which stops or replaces the current stream.
    case stopped
    /// Indicates that the audio stream has been paused.
    ///
    /// `temporary` true: Indicates taht the audio stream has been paused by `FocusState.background`.
    /// It will be resume when changed to `FocusState.foreground`.
    ///
    /// In this case, "playerActivity" in `AudioPlayerAgent`'s context is "PLAYING"
    case paused(temporary: Bool)
    /// Indicates that playback has finished.
    case finished
}

extension AudioPlayerState {
    var playerActivity: String {
        switch self {
        case .idle: return "IDLE"
        case .playing: return "PLAYING"
        case .stopped: return "STOPPED"
        case .paused(let temporary): return temporary ? "PLAYING" : "PAUSED"
        case .finished: return "FINISHED"
        }
    }
}

extension AudioPlayerState: Equatable {}
