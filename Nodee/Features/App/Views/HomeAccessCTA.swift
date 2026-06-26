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
    
     var body: some View {
         VStack(spacing: 12) {
             Image(systemName: "folder.badge.questionmark")
                 .font(.system(size: 34, weight: .light))
                 .foregroundStyle(.white.opacity(0.5))
             Text("Conceda acesso aos seus arquivos")
                 .font(.system(size: 15, weight: .semibold))
                 .foregroundStyle(.white.opacity(0.9))
             Text("O Nodee navega tudo dentro da sua pasta pessoal.\nSelecione-a uma vez para começar.")
                 .font(.system(size: 12))
                 .foregroundStyle(.white.opacity(0.55))
                 .multilineTextAlignment(.center)
             Button { Task { await panelVM.grantHomeAccess() } } label: {
                 Text("Conceder acesso à pasta pessoal")
                     .font(.system(size: 12, weight: .semibold))
                     .padding(.horizontal, 14)
                     .padding(.vertical, 8)
                     .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                     .foregroundStyle(.white)
             }
             .buttonStyle(.plain)
             .padding(.top, 4)
         }
         .frame(maxWidth: .infinity, maxHeight: .infinity)
         .background(Theme.panelBackground)
     }
}


