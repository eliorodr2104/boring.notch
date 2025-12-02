//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//  Modified by Eliomar Rodriguez on 01/12/2025.
//

import Combine
import Defaults
import SwiftUI

@MainActor
struct ContentView: View {
    
    @EnvironmentObject var viewModel: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var bluetoothManager = BluetoothManager.shared
    
    // MARK: - State
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?
    @State private var gestureProgress: CGFloat = .zero
    @State private var haptics: Bool = false
    
    // MARK: - Computed
    
    private var topCornerRadius: CGFloat {
        ((viewModel.notchState == .open) && Defaults[.cornerRadiusScaling])
        ? LayoutConfig.CornerRadius.opened.top : LayoutConfig.CornerRadius.closed.top
    }
    
    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((viewModel.notchState == .open) && Defaults[.cornerRadiusScaling])
            ? LayoutConfig.CornerRadius.opened.bottom : LayoutConfig.CornerRadius.closed.bottom
        )
    }
    
    private var horizontalPaddingBody: CGFloat {
        viewModel.notchState == .open ?
        Defaults[.cornerRadiusScaling] ?
        LayoutConfig.CornerRadius.opened.top :
        LayoutConfig.CornerRadius.opened.bottom :
        LayoutConfig.CornerRadius.closed.bottom
    }
    
    private var colorShadow: Color {
        ((viewModel.notchState == .open || isHovering) &&
         Defaults[.enableShadow]) ? .black.opacity(0.7) : .clear
    }
    
    private var shouldApplyFixedSize: Bool {
        let isSneakPeekShown = coordinator.sneakPeek.isShow
        let isMusic = coordinator.sneakPeek.type == .music
        let isClosed = viewModel.notchState == .closed
        let isStandardStyle = Defaults[.sneakPeekStyles] == .standard
        let hideOnClosed = viewModel.hideOnClosed

        if !isSneakPeekShown { return false }

        if isMusic && isClosed && !hideOnClosed && isStandardStyle {
            return true
        }
        
        if !isMusic && isClosed {
            return true
        }

        return false
    }
    
    var body: some View {
        let gestureScale: CGFloat = (gestureProgress != 0) ?
        max(0.6, 1.0 + gestureProgress * 0.01) : 1.0
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                
                mainNotchPill
                
                if self.viewModel.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(
                            width: viewModel.computedChinWidth,
                            height: viewModel.chinHeight
                        )
                        .allowsHitTesting(false)
                }
            }
            
        }
        .padding(.bottom, 8)
        .frame(
            maxWidth: LayoutConfig.windowSize.width,
            maxHeight: LayoutConfig.windowSize.height,
            alignment: .top
        )
        .compositingGroup()
        .scaleEffect(x: gestureScale, y: gestureScale, anchor: .top)
        .animation(.smooth, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(viewModel)
        .onChange(of: viewModel.anyDropZoneTargeting) { _, isTargeted in
            handleDropZoneChange(isTargeted: isTargeted)
        }
        .task(
            id: coordinator.expandingView,
            handleExpandingChange
        )
    }
    
    // MARK: - Views
    
    private var mainNotchPill: some View {
        VStack(alignment: .leading) {
            
            NotchContentRouter(
                isHovering: self.$isHovering,
                gestureProgress: self.$gestureProgress
            )
            
            // Overlay Sneak Peek
            if coordinator.sneakPeek.isShow {
                sneakPeekContent
            }
            
            if viewModel.notchState == .open {
                OpenNotchBodyView(gestureProgress: self.gestureProgress)
            }
        }
        .frame(alignment: .top)
        .padding(.horizontal, self.horizontalPaddingBody)
        .padding([.horizontal, .bottom], viewModel.notchState == .open ? 12 : 0)
        .background(.black)
        .clipShape(currentNotchShape)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.black)
                .frame(height: 1)
                .padding(.horizontal, topCornerRadius)
        }
        .shadow(
            color: self.colorShadow,
            radius: Defaults[.cornerRadiusScaling] ? 6 : 4
        )
        .padding(.bottom, viewModel.effectiveClosedNotchHeight == 0 ? 10 : 0)
        .frame(height: viewModel.notchState == .open ? viewModel.notchSize.height : nil)
        .animation(
            viewModel.notchState == .open ?
                .spring(response: 0.42, dampingFraction: 0.8) :
                .spring(response: 0.45, dampingFraction: 1.0),
            value: viewModel.notchState
        )
        .animation(.smooth, value: gestureProgress)
        .contentShape(Rectangle())
        .onHover { handleHover($0) }
        .onTapGesture { doOpen() }
        .conditionalModifier(Defaults[.enableGestures]) { view in
            self.handlerDownGesture(view)
        }
        .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
            self.handlerUpGesture(view)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
            handleSharingDidFinish()
        }
        .onChange(of: viewModel.notchState) { _, newState in
            if newState == .closed && isHovering {
                withAnimation { isHovering = false }
            }
        }
        .onChange(of: viewModel.isBatteryPopoverActive) { handleBatteryPopoverChange() }
        .sensoryFeedback(.alignment, trigger: haptics)
        .contextMenu {
            Button("Settings") { SettingsWindowController.shared.showWindow() }
                .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
        }
        .onDrop(
            of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
            delegate: GeneralDropTargetDelegate(isTargeted: $viewModel.generalDropTargeting)
        )
        .conditionalModifier(shouldApplyFixedSize) { view in
            view.fixedSize()
        }
        .zIndex(2)
    }
    
    @ViewBuilder
    private var sneakPeekContent: some View {
        if shouldShowSystemEvents {
            SystemEventIndicatorModifier(
                eventType: $coordinator.sneakPeek.type,
                value: $coordinator.sneakPeek.value,
                icon: $coordinator.sneakPeek.icon,
                sendEventBack: { newVal in
                    if coordinator.sneakPeek.type == .volume { VolumeManager.shared.setAbsolute(Float32(newVal)) }
                    else if coordinator.sneakPeek.type == .brightness { BrightnessManager.shared.setAbsolute(value: Float32(newVal)) }
                }
            )
            .padding(.bottom, 10).padding(.leading, 4).padding(.trailing, 8)
            
        } else if coordinator.sneakPeek.type == .music && viewModel.notchState == .closed && !viewModel.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
//            HStack(alignment: .center) {
//                Image(systemName: "music.note")
//                GeometryReader { geo in
//                    MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName), textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
//                }
//            }.foregroundStyle(.gray).padding(.bottom, 10)
        }
    }
    
    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && viewModel.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $viewModel.dragDetectorTargeting) { providers in
                    viewModel.dropEvent = true
                    ShelfStateViewModel.shared.load(providers)
                    return true
                }
        } else {
            EmptyView()
        }
    }
    
    // MARK: - Handles
    
    private var shouldShowSystemEvents: Bool {
        coordinator.sneakPeek.isShow &&
        (coordinator.sneakPeek.type != .music) &&
        (coordinator.sneakPeek.type != .battery) &&
        !Defaults[.inlineHUD] &&
        viewModel.notchState == .closed
    }

    private func doOpen() {
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)) {
            viewModel.open()
        }
    }
    
    private func handleSharingDidFinish() {
        if viewModel.notchState == .open &&
           !isHovering &&
           !viewModel.isBatteryPopoverActive {
            
            hoverTask?.cancel()
            
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if !SharingStateManager.shared.preventNotchClose {
                        self.viewModel.close()
                    }
                }
            }
        }
    }
    
    private func handleBatteryPopoverChange() {
        if !viewModel.isBatteryPopoverActive &&
            !isHovering &&
            viewModel.notchState == .open &&
            !SharingStateManager.shared.preventNotchClose {
            
            hoverTask?.cancel()
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run { self.viewModel.close() }
            }
        }
    }
    
    private func handleDropZoneChange(isTargeted: Bool) {
        anyDropDebounceTask?.cancel()
        if isTargeted {
            if viewModel.notchState == .closed {
                coordinator.currentView = .shelf
                doOpen()
            }
            
            return
        }
        
        anyDropDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            
            if viewModel.dropEvent {
                viewModel.dropEvent = false
                return
            }
            
            viewModel.dropEvent = false
            if !SharingStateManager.shared.preventNotchClose { viewModel.close() }
        }
    }
    
    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(
                .interactiveSpring(
                    response: 0.38,
                    dampingFraction: 0.8,
                    blendDuration: 0)
            ) { isHovering = true }
            
            if viewModel.notchState == .closed &&
               Defaults[.enableHaptics] { haptics.toggle() }
            
            guard viewModel.notchState == .closed,
                  !coordinator.sneakPeek.isShow,
                  Defaults[.openNotchOnHover]
            else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.viewModel.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.isShow
                    else { return }
                    
                    self.doOpen()
                }
            }
            
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(
                        .interactiveSpring(
                            response: 0.38,
                            dampingFraction: 0.8,
                            blendDuration: 0)
                    ) { self.isHovering = false }
                    
                    if self.viewModel.notchState == .open && !self.viewModel.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        
                        self.viewModel.close()
                    }
                }
            }
        }
    }
    
    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard viewModel.notchState == .closed else { return }
        
        if phase == .ended {
            withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) {
                gestureProgress = .zero
            }
            
            return
        }
        
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }
        
        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] { haptics.toggle() }
            withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) {
                gestureProgress = .zero
            }
            
            doOpen()
        }
    }
    
    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard viewModel.notchState == .open &&
              !viewModel.isHoveringCalendar
        else { return }
        
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }
        
        if phase == .ended {
            withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) {
                gestureProgress = .zero
            }
        }
        
        if translation > Defaults[.gestureSensitivity] {
            withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8)) {
                isHovering = false
            }
            
            if !SharingStateManager.shared.preventNotchClose {
                gestureProgress = .zero
                viewModel.close()
            }
            
            if Defaults[.enableHaptics] { haptics.toggle() }
        }
    }
    
    private func handlerDownGesture<V: View>(_ view: V) -> some View {
        view.panGesture(direction: .down) { transition, phase in
            self.handleDownGesture(translation: transition, phase: phase)
        }
    }
    
    private func handlerUpGesture<V: View>(_ view: V) -> some View {
        view.panGesture(direction: .up) { transition, phase in
            handleUpGesture(translation: transition, phase: phase)
        }
    }
    
    @Sendable
    private func handleExpandingChange() async {
        guard coordinator.expandingView.isShow else { return }

        let duration: TimeInterval = (coordinator.expandingView.type == .download ? 2 : 3)

        try? await Task.sleep(for: .seconds(duration))

        guard !Task.isCancelled else { return }
        
        coordinator.toggleExpandingView(
            status: false,
            type  : .unknown
        )
    }
}

// MARK: - Drop Delegates

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    
    func dropEntered(info: DropInfo) {
        self.isTargeted = true
    }
    
    func dropExited(info: DropInfo) {
        self.isTargeted = false
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}
