//
//  HeadphoneStatusView.swift
//  boringNotch
//
//  Created by Eliomar Alejandro Rodriguez Ferrer on 02/12/25.
//

import SwiftUI

struct HeadphoneStatusView: View {
    
    @EnvironmentObject
    var viewModel: BoringViewModel
    
    @ObservedObject
    var bluetoothManager = BluetoothManager.shared
    
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Image(systemName: self.bluetoothManager.currentHeadphone!.icon)
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            
            Rectangle().fill(.black)
                .frame(width: self.viewModel.closedNotchSize.width + 10)
            
            HStack {
                EmptyView()
            }
            .frame(width: 76, alignment: .trailing)
            
        }
        .frame(height: self.viewModel.effectiveClosedNotchHeight, alignment: .center)
    }
}
