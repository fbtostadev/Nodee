//
//  HomeAccessCTA.swift
//  Nodee
//
//  Created by Wise on 25/06/26.
//

import SwiftUI
import SwiftData
import Foundation

 struct homeAccessCTA: View {

     let panelVM: PanelViewModel

     @State private var isGranting = false

     var body: some View {
         VStack(spacing: 12) {
             Image(systemName: "folder.badge.plus")
                 .font(.system(size: 34, weight: .light))
                 .foregroundStyle(Color.accentColor)
             Text("Bem-vindo ao Nodee")
                 .font(.system(size: 15, weight: .semibold))
                 .foregroundStyle(.white.opacity(0.9))
             Text("Conceda acesso às suas pastas uma vez\npara navegar seus arquivos direto do notch.")
                 .font(.system(size: 12))
                 .foregroundStyle(.white.opacity(0.55))
                 .multilineTextAlignment(.center)
             Button(action: grant) {
                 Text(isGranting ? "Concedendo…" : "Conceder acesso às pastas")
                     .font(.system(size: 12, weight: .semibold))
                     .padding(.horizontal, 14)
                     .padding(.vertical, 8)
                     .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                     .foregroundStyle(.white)
             }
             .buttonStyle(.plain)
             .disabled(isGranting)
             .padding(.top, 4)
         }
         .frame(maxWidth: .infinity, maxHeight: .infinity)
         .background(Theme.panelBackground)
     }

     private func grant() {
         guard !isGranting else { return }
         isGranting = true
         Task {
             await panelVM.grantHomeAccess()
             isGranting = false
         }
     }
}


