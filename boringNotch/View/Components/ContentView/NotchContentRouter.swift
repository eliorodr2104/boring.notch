//
//  NotchPillView.swift
//  boringNotch
//
//  Created by Eliomar Alejandro Rodriguez Ferrer on 01/12/25.
//

import SwiftUI
import Defaults

struct NotchContentRouter: View {
    @EnvironmentObject
    private var viewModel: BoringViewModel
    
    @Binding
    var isHovering: Bool
    
    @Binding
    var gestureProgress: CGFloat
    
    var body: some View {
        ZStack {
            switch self.viewModel.currentContentState {
                
                case .hello:
                    HelloAnimationView()
                    .transition(.opacity)
                    
                case .battery:
                    BatteryStatusView()
                    .transition(.opacity)
                    
                case .inlineHUD:
                    InlineHUDView(
                        isHovering: self.$isHovering,
                        gestureProgress: self.$gestureProgress
                    )
                    .transition(.expandHorizontally)
                    .zIndex(1)
                
                case .headphones:
                    HeadphoneStatusView()
                    .transition(.opacity)
                    
                case .music:
                    MusicLiveActivityView()
                    .transition(.opacity)
                    
                case .boringFace:
                    BoringFaceView()
                    .transition(.opacity)
                    
                case .open:
                    BoringHeaderView()
                        .frame(height: max(24, viewModel.effectiveClosedNotchHeight))
                        .transition(.opacity)
                    
                case .empty:
                    Rectangle()
                    .fill(.clear)
                    .frame(width: viewModel.closedNotchSize.width - 20, height: viewModel.effectiveClosedNotchHeight)
                    .transition(.identity)
            
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: viewModel.currentContentState)
    }
}
