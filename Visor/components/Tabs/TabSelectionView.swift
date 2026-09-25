//
//  TabSelectionView.swift
//  
//
//  Created by Apurva on 2024-08-25.
//

import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(icon: "house.fill", view: .home),
    TabModel(icon: "tray.fill", view: .shelf)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = VisorViewCoordinator.shared
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                // Visor: TabButton's label and selected parameters were unused;
                // its button is inline here.
                Button {
                    withAnimation(.smooth) {
                        coordinator.currentView = tab.view
                    }
                } label: {
                    Image(systemName: tab.icon)
                        .padding(.horizontal, 15)
                        .contentShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                .frame(height: 26)
                .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                .background {
                    if tab.view == coordinator.currentView {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }
            }
        }
        .clipShape(Capsule())
    }
}
