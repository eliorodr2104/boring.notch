//
//  InlineHUDView.swift
//  boringNotch
//
//  Created by Eliomar Alejandro Rodriguez Ferrer on 01/12/25.
//

import SwiftUI

struct InlineHUDView: View {
    @ObservedObject
    var coordinator = BoringViewCoordinator.shared
    
    @Binding
    var isHovering: Bool
    
    @Binding
    var gestureProgress: CGFloat
    
    var body: some View {
        
        InlineHUD(
            type: $coordinator.sneakPeek.type,
            value: $coordinator.sneakPeek.value,
            icon: $coordinator.sneakPeek.icon,
            hoverAnimation: $isHovering,
            gestureProgress: $gestureProgress
        )
    }
}

struct HorizontalStretchModifier: ViewModifier {
    let completion: CGFloat // 0 = stretto, 1 = largo

    func body(content: Content) -> some View {
        content
            // x: completion -> si allarga
            // y: 1 -> altezza fissa
            // anchor: .center -> si allarga simmetricamente dal centro
            .scaleEffect(x: completion, y: 1, anchor: .center)
    }
}

extension AnyTransition {
    static var expandHorizontally: AnyTransition {
        .modifier(
            active: HorizontalStretchModifier(completion: 0.3), // Non partire da 0, parti dalla larghezza della notch "vuota" (circa 30%)
            identity: HorizontalStretchModifier(completion: 1)
        )
        // Aggiungiamo l'opacità per rendere l'ingresso più morbido
        .combined(with: .opacity)
    }
}
