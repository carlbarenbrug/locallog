//
//  VideoPlayerView.swift
//  LocalLog
//
//  Created by Claude Code
//

import SwiftUI
import AVKit
import AVFoundation
import AppKit

private struct FillVideoPlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    let shouldAutoPlay: Bool
    let focusRingColor: NSColor
    
    final class PlayerContainerView: NSView {
        private let playerView = AVPlayerView()

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        private func setup() {
            wantsLayer = true
            layer?.masksToBounds = true

            playerView.translatesAutoresizingMaskIntoConstraints = false
            playerView.controlsStyle = .floating
            playerView.videoGravity = .resizeAspectFill
            playerView.showsFrameSteppingButtons = false
            playerView.updatesNowPlayingInfoCenter = false
            playerView.focusRingType = .none

            addSubview(playerView)
            NSLayoutConstraint.activate([
                playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                playerView.topAnchor.constraint(equalTo: topAnchor),
                playerView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        func setPlayer(_ player: AVPlayer, shouldAutoPlay: Bool, focusRingColor: NSColor) {
            if playerView.player !== player {
                playerView.player = player
            }
            player.isMuted = false
            player.volume = 1.0
            playerView.showsSharingServiceButton = false
            playerView.showsFullScreenToggleButton = false
            playerView.showsFrameSteppingButtons = false
            playerView.layer?.borderWidth = 0
            playerView.layer?.borderColor = focusRingColor.cgColor
            if !shouldAutoPlay {
                playerView.window?.makeFirstResponder(nil)
            }
        }
    }

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.setPlayer(player, shouldAutoPlay: shouldAutoPlay, focusRingColor: focusRingColor)
        return view
    }
    
    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        nsView.setPlayer(player, shouldAutoPlay: shouldAutoPlay, focusRingColor: focusRingColor)
    }
}

struct VideoPlayerView: View {
    let videoURL: URL
    let isPlaybackSuspended: Bool
    let shouldAutoPlay: Bool
    @State private var player = AVPlayer()
    @State private var playbackStatusObservation: NSKeyValueObservation?
    @State private var playbackProgressObserver: Any?
    @State private var itemStatusObservation: NSKeyValueObservation?
    @State private var configuredVideoURL: URL?
    @State private var hasRevealedCurrentItem = false
    @State private var currentItemReadyToPlay = false
    @State private var playerIsActivelyPlaying = false
    @State private var playbackSecondsForCurrentItem: Double = 0

    var body: some View {
        ZStack {
            FillVideoPlayerSurface(
                player: player,
                shouldAutoPlay: shouldAutoPlay,
                focusRingColor: NSColor(white: 0.55, alpha: 0.9)
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .opacity(hasRevealedCurrentItem ? 1 : 0)
                .animation(.easeOut(duration: 0.75), value: hasRevealedCurrentItem)

            if !hasRevealedCurrentItem {
                Color.white
                    .overlay(alignment: .center) {
                        ProgressView()
                            .controlSize(.small)
                            .progressViewStyle(CircularProgressViewStyle(tint: Color.gray.opacity(0.8)))
                            .scaleEffect(1.1)
                    }
            }
        }
        .onAppear {
            player.isMuted = false
            player.volume = 1.0
            player.actionAtItemEnd = .pause
            player.automaticallyWaitsToMinimizeStalling = false
            observePlaybackState()
            configurePlayer(for: videoURL)
            applyPlaybackSuspension(isPlaybackSuspended)
        }
        .onChange(of: videoURL) { _, _ in
            configurePlayer(for: videoURL)
        }
        .onChange(of: isPlaybackSuspended) { _, isSuspended in
            applyPlaybackSuspension(isSuspended)
        }
        .onDisappear {
            tearDownPlayer()
        }
    }

    private func configurePlayer(for url: URL) {
        if configuredVideoURL == url {
            hasRevealedCurrentItem = false
            currentItemReadyToPlay = false
            playbackSecondsForCurrentItem = 0
            player.isMuted = false
            player.volume = 1.0
            player.seek(to: .zero)
            if shouldAutoPlay && !isPlaybackSuspended {
                player.playImmediately(atRate: 1.0)
            }
            return
        }

        clearItemObservers()
        hasRevealedCurrentItem = false
        currentItemReadyToPlay = false
        playbackSecondsForCurrentItem = 0

        let item = AVPlayerItem(url: url)
        itemStatusObservation = item.observe(\.status, options: [.new]) { _, _ in
            DispatchQueue.main.async {
                if item.status == .readyToPlay {
                    self.currentItemReadyToPlay = true
                    self.revealVideoWhenReady()
                    if self.shouldAutoPlay && !self.isPlaybackSuspended {
                        self.player.playImmediately(atRate: 1.0)
                    }
                }
            }
        }

        player.replaceCurrentItem(with: item)
        player.isMuted = false
        player.volume = 1.0
        configuredVideoURL = url

        if shouldAutoPlay && !isPlaybackSuspended {
            player.playImmediately(atRate: 1.0)
        }
    }
    
    private func tearDownPlayer() {
        clearItemObservers()
        playbackStatusObservation = nil
        if let progressObserver = playbackProgressObserver {
            player.removeTimeObserver(progressObserver)
            playbackProgressObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        configuredVideoURL = nil
        hasRevealedCurrentItem = false
        currentItemReadyToPlay = false
        playerIsActivelyPlaying = false
        playbackSecondsForCurrentItem = 0
    }

    private func clearItemObservers() {
        itemStatusObservation = nil
    }

    private func observePlaybackState() {
        guard playbackStatusObservation == nil else { return }
        playbackStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { player, _ in
            DispatchQueue.main.async {
                self.playerIsActivelyPlaying = player.timeControlStatus == .playing
                self.revealVideoWhenReady()
            }
        }

        guard playbackProgressObserver == nil else { return }
        playbackProgressObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { time in
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite && seconds >= 0 {
                self.playbackSecondsForCurrentItem = seconds
            } else {
                self.playbackSecondsForCurrentItem = 0
            }
            self.revealVideoWhenReady()
        }
    }

    private func revealVideoWhenReady() {
        guard !hasRevealedCurrentItem else { return }
        guard !isPlaybackSuspended else { return }
        guard currentItemReadyToPlay else { return }
        if shouldAutoPlay {
            guard playerIsActivelyPlaying, playbackSecondsForCurrentItem >= 1.0 else { return }
        }
        withAnimation(.easeOut(duration: 0.75)) {
            hasRevealedCurrentItem = true
        }
    }

    private func applyPlaybackSuspension(_ suspended: Bool) {
        if suspended {
            player.pause()
        } else if shouldAutoPlay && player.currentItem != nil {
            player.playImmediately(atRate: 1.0)
        }
    }
}
