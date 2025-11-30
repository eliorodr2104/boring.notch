//
//  HStack+If.swift
//  boringNotch
//
//  Created by Eliomar Alejandro Rodriguez Ferrer on 30/11/25.
//

import SwiftUI

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
