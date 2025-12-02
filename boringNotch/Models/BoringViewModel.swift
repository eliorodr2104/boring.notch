//
//  BoringViewModel.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import SwiftUI

class BoringViewModel: NSObject, ObservableObject {
    var coordinator = BoringViewCoordinator.shared
    
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: BoringAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []
    
    @Published
    var hideOnClosed: Bool = true

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()
    
    let webcamManager = WebcamManager.shared
    @Published var isCameraExpanded: Bool = false
    @Published var isRequestingAuthorization: Bool = false
    
    deinit {
        destroy()
    }
    
    // MARK: - Computed variables
    
    var currentContentState: NotchContentState {
        if self.coordinator.helloAnimationRunning { return .hello }
            
        // Logica per determinare cosa mostrare quando è chiuso
        if self.notchState == .closed {
            if isBatteryNotificationActive { return .battery    }
            if isInlineHUDActive           { return .inlineHUD  }
            if isMusicLiveActivityActive   { return .music      }
            if isBoringFaceActive          { return .boringFace }
            if isHeadphonesStatusActive    { return .headphones }
            
            return .empty
        }
            
        if notchState == .open { return .open }
            
        return .empty
    }

    // Calcolo della larghezza del "mento"
    var computedChinWidth: CGFloat {
        let width: CGFloat = closedNotchSize.width
            
        switch currentContentState {
            case .battery:
                return 640
            
            case .music, .boringFace:
                return width + (2 * max(0, effectiveClosedNotchHeight - 12) + 20)
            
            default:
                return width
        }
    }
        
    // Helpers estratti dalla View
    private var isBatteryNotificationActive: Bool {
        BoringViewCoordinator.shared.expandingView.type == .battery &&
        notchState == .closed &&
        Defaults[.showPowerStatusNotifications]
    }
        
    private var isInlineHUDActive: Bool {
        
        return coordinator.sneakPeek.isShow &&
        Defaults[.inlineHUD] &&
        coordinator.sneakPeek.type != .music &&
        coordinator.sneakPeek.type != .battery &&
        coordinator.sneakPeek.type != .headphones &&
        notchState == .closed
    }
    
    private var isHeadphonesStatusActive: Bool {
        return coordinator.sneakPeek.isShow &&
                coordinator.sneakPeek.type == .headphones &&
                notchState == .closed
    }
        
    private var isMusicLiveActivityActive: Bool {
        let musicManager = MusicManager.shared
            
        return (
            !coordinator.expandingView.isShow ||
             coordinator.expandingView.type == .music
        ) && notchState == .closed &&
        (musicManager.isPlaying || !musicManager.isPlayerIdle) &&
        coordinator.musicLiveActivityEnabled && !hideOnClosed
    }
        
    private var isBoringFaceActive: Bool {
        let musicManager = MusicManager.shared
            
        return !coordinator.expandingView.isShow &&
        notchState == .closed &&
        (!musicManager.isPlaying && musicManager.isPlayerIdle) &&
        Defaults[.showNotHumanFace] &&
        !hideOnClosed
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil) {
        animation = animationLibrary.animation

        super.init()
        
        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        Publishers.CombineLatest3($dropZoneTargeting, $dragDetectorTargeting, $generalDropTargeting)
            .map { shelf, drag, general in
                shelf || drag || general
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)
        
        setupDetectorObserver()
    }
    
    private func setupDetectorObserver() {
        // Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        // Publisher for the current screen UUID (non-nil, distinct)
        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        // Publisher for fullscreen status dictionary
        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        // Combine all three: screen UUID, fullscreen status, and enabled setting
        Publishers.CombineLatest3(
            screenPublisher,
            fullscreenStatusPublisher,
            enabledPublisher
        )
        .map { screenUUID, fullscreenStatus, enabled in
            let isFullscreen = fullscreenStatus[screenUUID] ?? false
            return enabled && isFullscreen
        }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { [weak self] shouldHide in
            withAnimation(.smooth) {
                self?.hideOnClosed = shouldHide
            }            
        }
        .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.with(uuid: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.with(uuid: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func toggleCameraPreview() {
        if isRequestingAuthorization {
            return
        }

        switch webcamManager.authorizationStatus {
        case .authorized:
            if webcamManager.isSessionRunning {
                webcamManager.stopSession()
                isCameraExpanded = false
                
            } else if webcamManager.cameraAvailable {
                webcamManager.startSession()
                isCameraExpanded = true
            }

        case .denied, .restricted:
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                let alert = NSAlert()
                alert.messageText = "Camera Access Required"
                alert.informativeText = "Please allow camera access in System Settings."
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }

                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }

        case .notDetermined:
            isRequestingAuthorization = true
            webcamManager.checkAndRequestVideoAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.isRequestingAuthorization = false
            }

        default:
            break
        }
    }
    
    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screenUUID)
        if let frame = screenFrame {
            
            let baseY = frame.maxY - notchSize.height
            let baseX = frame.midX - notchSize.width / 2
            
            return position.y >= baseY && position.x >= baseX && position.x <= baseX + notchSize.width
        }
        
        return false
    }

    func open() {
        self.notchSize = LayoutConfig.openNotchSize
        self.notchState = .open
        
        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
    }

    func close() {
        // Do not close while a share picker or sharing service is active
        if SharingStateManager.shared.preventNotchClose {
            return
        }
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isBatteryPopoverActive = false
        self.coordinator.sneakPeek.isShow = false
        self.edgeAutoOpenActive = false

        // Set the current view to shelf if it contains files and the user enables openShelfByDefault
        // Otherwise, if the user has not enabled openLastShelfByDefault, set the view to home
    if !ShelfStateViewModel.shared.isEmpty && Defaults[.openShelfByDefault] {
            coordinator.currentView = .shelf
        } else if !coordinator.openLastTabByDefault {
            coordinator.currentView = .home
        }
    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(animationLibrary.animation) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }
}
