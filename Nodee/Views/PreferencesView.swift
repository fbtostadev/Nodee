//
//  PreferencesView.swift
//  Nodee
//
//  Minimal preferences. The configurable global shortcut UI lands here; for now
//  it documents the default (⌥⌘N). The Notch gesture remains the primary way in.
//

import SwiftUI

struct PreferencesView: View {
    var body: some View {
        Form {
            Section("Atalho") {
                LabeledContent("Abrir / fechar o painel", value: "⌥⌘N")
                Text("O gesto do Notch é o método primário. O atalho global é opcional e será configurável.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Sobre") {
                LabeledContent("Nodee", value: "v0 · conceito")
                Text("Gerenciador de arquivos espacial que vive no Notch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 280)
    }
}
