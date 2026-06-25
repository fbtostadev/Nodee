//
//  BrowserContextMenu.swift
//  Nodee
//
//  The file-operation menu shared by the List and Columns surfaces. Right-clicking
//  an item targets it (selecting it first if it wasn't already), then offers the
//  operations that make Nodee a real Finder replacement.
//

import SwiftUI

@MainActor
@ViewBuilder
func fileContextMenu(vm: BrowserViewModel, file: FileNode) -> some View {
    let target: () -> Void = {
        if !vm.selection.contains(file.url) { vm.select(file.url) }
    }

    Button(file.isDirectory ? "Abrir" : "Abrir no app padrão") {
        target(); vm.open(file)
    }
    Button("Renomear") {
        target(); vm.beginRename(file.url)
    }

    Button("Mostrar no Finder") { target(); vm.revealInFinder() }
    Button("Copiar caminho") { target(); vm.copyPath() }

    Divider()

    Button("Duplicar") { target(); vm.duplicateSelection() }
    Button("Copiar") { target(); vm.copySelection() }
    Button("Colar") { vm.paste() }
        .disabled(vm.clipboard.isEmpty)

    Divider()

    // No target() needed: these create in the active directory, not on the item.
    Button("Novo arquivo") { vm.newFile() }
    Button("Nova pasta") { vm.newFolder() }

    Divider()

    Button("Mover para Lixeira", role: .destructive) {
        target(); vm.trashSelection()
    }
}
