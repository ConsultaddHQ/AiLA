import AppKit
import Combine
import SwiftUI

final class NotchWindow {
    private var window: NSWindow!
    private let viewModel: InterviewViewModel
    private var cancellables: Set<AnyCancellable> = []

    init(viewModel: InterviewViewModel) {
        self.viewModel = viewModel

        let contentView = NotchHUDView(vm: viewModel)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 0
            ))

        let hosting = NSHostingView(rootView: contentView)
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = true

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: viewModel.hudWidth, height: viewModel.hudHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.hasShadow = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.contentView = hosting
        window.ignoresMouseEvents = false

        viewModel.$hudWidth
            .combineLatest(viewModel.$hudHeight)
            .receive(on: RunLoop.main)
            .sink { [weak self] width, height in
                self?.resize(width: width, height: height)
            }
            .store(in: &cancellables)

        viewModel.$selectedScreenIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.resize(width: self.viewModel.hudWidth, height: self.viewModel.hudHeight)
            }
            .store(in: &cancellables)

        viewModel.$horizontalAlignment
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.resize(width: self.viewModel.hudWidth, height: self.viewModel.hudHeight)
            }
            .store(in: &cancellables)

        viewModel.$isHUDVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in
                if isVisible {
                    self?.animateShow()
                } else {
                    self?.animateHide()
                }
            }
            .store(in: &cancellables)

        viewModel.$hideFromScreenRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] hide in
                self?.updateScreenRecordingVisibility(hide)
            }
            .store(in: &cancellables)

        updateScreenRecordingVisibility(viewModel.hideFromScreenRecording)
    }

    func show() {
        guard let screen = selectedScreen() else {
            window.center()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let frame = topCenterFrame(width: viewModel.hudWidth, height: viewModel.hudHeight, screen: screen)
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func resize(width: CGFloat, height: CGFloat) {
        guard let screen = selectedScreen() else { return }
        let frame = topCenterFrame(width: width, height: height, screen: screen)
        window.setFrame(frame, display: true, animate: true)
    }

    private func selectedScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let index = viewModel.selectedScreenIndex
        if index >= 0 && index < screens.count {
            return screens[index]
        }
        return NSScreen.main
    }

    private func topCenterFrame(width: CGFloat, height: CGFloat, screen: NSScreen) -> CGRect {
        let alignmentPosition: CGFloat = {
            switch viewModel.horizontalAlignment {
            case .left: return 0.0
            case .center: return 0.5
            case .right: return 1.0
            }
        }()
        let padding: CGFloat = 20
        let availableWidth = screen.frame.width - width - (padding * 2)
        let x = screen.frame.minX + padding + (availableWidth * alignmentPosition)
        let topBorderHide: CGFloat = 4
        let y = screen.frame.maxY - height + topBorderHide
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func updateScreenRecordingVisibility(_ hide: Bool) {
        if hide {
            window.sharingType = .none
        } else {
            window.sharingType = .readOnly
        }
    }

    private let animationSpeed = 0.25

    private func animateShow() {
        guard let screen = selectedScreen() else { return }
        let finalFrame = topCenterFrame(width: viewModel.hudWidth, height: viewModel.hudHeight, screen: screen)
        var startFrame = finalFrame
        startFrame.origin.y = screen.frame.maxY
        window.setFrame(startFrame, display: false)
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animationSpeed
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(finalFrame, display: true)
        }
    }

    private func animateHide() {
        guard let screen = selectedScreen() else {
            window.orderOut(nil)
            return
        }
        var targetFrame = window.frame
        targetFrame.origin.y = screen.frame.maxY
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = animationSpeed
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(targetFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.window.orderOut(nil)
        })
    }
}
