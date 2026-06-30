//
//  ToolbalView.swift
//  Nodee
//
//  Created by Wise on 26/06/26.
//

import SwiftUI
import Foundation

struct ToolbarView: View {
    @Binding var selection: Features
    
    var body: some View {
        HStack {
            
            
            Button {
                selection = .fileManager
            } label: {
                Image(systemName: selection == .fileManager ? "folder.fill" : "folder")
            }
            
            Button {
                selection = .timer
            } label: {
                Image(systemName: selection == .timer ? "clock.fill" : "clock")
            }
            
            Button {
                selection = .notes
            } label: {
                Image(systemName: selection == .notes ? "long.text.page.and.pencil.fill" : "long.text.page.and.pencil")
            }
            
            Button {
                selection = .mediaPlayer
            } label: {
                Image(systemName: selection == .mediaPlayer ? "play.fill" : "play")
            }
            Spacer()
            
        }
        .padding()
        .buttonStyle(PlainButtonStyle())
    }
}



enum Features {
    case fileManager
    case timer
    case notes
    case mediaPlayer
}


#Preview {
    @Previewable @State var selection = Features.fileManager
    
    ToolbarView(selection: $selection)
    
}
