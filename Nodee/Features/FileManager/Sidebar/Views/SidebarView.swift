//
//  SidebarView.swift
//  Nodee
//
//  Finder-style sidebar: a "Locais" section (standard folders derived from the
//  granted Home) and a "Favoritos" section (user-pinned folders, persisted as
//  security-scoped bookmarks). Favorite a folder by dragging it from Finder or
//  via the + button. Removing a favorite never touches the folder on disk.
//

import SwiftUI
import SwiftData
import AppKit

struct SidebarView: View {
    @Environment(PanelPresentation.self) private var presentation

    let vm: SidebarViewModel
    let locations: [SidebarLocation]
    let projects: [PinnedProject]
    /// The directory currently in view — used to light up the matching Location.
    let currentDirectory: URL?
    /// The favorite explicitly opened (highlight that survives drilling into it).
    let selectedFavoriteID: UUID?
    let width: CGFloat
    let onSelectLocation: (SidebarLocation) -> Void
    let onSelectFavorite: (PinnedProject) -> Void
    let onCollapse: () -> Void
    /// Files dropped onto a favorite's row: move them into it on disk (copy when
    /// ⌥ is held). Implemented by PanelRootView, which owns the browser VM.
    let onDropFiles: (_ urls: [URL], _ project: PinnedProject, _ copy: Bool) -> Void
    /// Files dropped onto a Location's row: move (or ⌥-copy) them into that folder.
    /// Locations live under the Home grant, so the URL is moved into directly.
    let onDropIntoLocation: (_ urls: [URL], _ folder: URL, _ copy: Bool) -> Void

    @State private var isDropTargeted = false
    /// The favorite row a drag is currently hovering over (for the drop highlight).
    @State private var dropTargetID: UUID?
    /// The Location row a drag is currently hovering over (for the drop highlight).
    @State private var dropTargetLocationID: URL?
    /// Hover tracking — separate from drop so hovering without a drag also shows feedback.
    @State private var hoveredLocationID: URL?
    @State private var hoveredFavID: UUID?

    /// The Location whose folder is the deepest ancestor of (or equal to) the
    /// current directory — the one to highlight. Nil when an explicit favorite is
    /// selected (its highlight takes over).
    private var activeLocationURL: URL? {
        guard selectedFavoriteID == nil, let current = currentDirectory?.standardizedFileURL.path else { return nil }
        return locations
            .filter { current == $0.url.standardizedFileURL.path || current.hasPrefix($0.url.standardizedFileURL.path + "/") }
            .max { $0.url.standardizedFileURL.path.count < $1.url.standardizedFileURL.path.count }?
            .url
    }

    var body: some View {
        let totalWidth = width + presentation.sidebarTrailingReveal * Theme.paneHandleGutter
        // Header and content are pinned to the base width; the Divider spans the
        // full totalWidth so it fills the gutter that opens as the collapse handle
        // nears — without reflowing any text or row content.
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(width: width, alignment: .leading)
            Divider().overlay(Color.white.opacity(0.08))
            content
                .frame(width: width, alignment: .leading)
        }
        .frame(width: totalWidth, alignment: .leading)
        .animation(.smooth(duration: 0.35), value: presentation.sidebarTrailingReveal)
        .overlay {
            // The whole-sidebar "favorite here" border — suppressed while a
            // specific favorite or location row is the drop target (it shows its own).
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(showsPinBorder ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.16), value: showsPinBorder)
    }

    /// Whether the whole-sidebar "favorite here" border should show: a drag is over
    /// the sidebar but not over any specific row (those show their own highlight).
    private var showsPinBorder: Bool {
        isDropTargeted && dropTargetID == nil && dropTargetLocationID == nil
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Nodee")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button(action: onCollapse) {
                Image(systemName: "square.lefthalf.filled")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.45))
            .help("Recolher sidebar")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if !locations.isEmpty {
                    sectionHeader("Locais")
                    ForEach(locations) { location in
                        locationRow(location)
                    }
                }

                favoritesHeader
                    .padding(.top, locations.isEmpty ? 0 : 10)
                ForEach(projects) { project in
                    favoriteRow(project)
                }
            }
            .padding(8)
        }
        // "Favorite a folder here" drop sits *behind* the rows, so a drop onto a
        // favorite row hits that row's own destination (move into it) instead of
        // being swallowed by this whole-sidebar one. Only drops on empty space
        // fall through to here and pin.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .dropDestination(for: URL.self) { urls, _ in
                    vm.pin(urls, existingProjects: projects); return true
                } isTargeted: { isDropTargeted = $0 }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }

    private var favoritesHeader: some View {
        HStack {
            Text("FAVORITOS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
            Spacer()
            Button { vm.addViaPanel(existingProjects: projects) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
            .help("Adicionar pasta aos favoritos")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Rows

    private func locationRow(_ location: SidebarLocation) -> some View {
        let isSelected = location.url.standardizedFileURL == activeLocationURL?.standardizedFileURL
        let isDropTarget = location.id == dropTargetLocationID
        let isHovered = location.id == hoveredLocationID
        return rowLabel(systemImage: location.systemImage, name: location.name,
                        isSelected: isSelected, isDropTarget: isDropTarget, isHovered: isHovered)
            .contentShape(Rectangle())
            .onTapGesture { onSelectLocation(location) }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    hoveredLocationID = hovering ? location.id : (hoveredLocationID == location.id ? nil : hoveredLocationID)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                onDropIntoLocation(urls, location.url, NSEvent.modifierFlags.contains(.option))
                return true
            } isTargeted: { targeted in
                dropTargetLocationID = targeted ? location.id : (dropTargetLocationID == location.id ? nil : dropTargetLocationID)
            }
    }

    private func favoriteRow(_ project: PinnedProject) -> some View {
        let isSelected = project.id == selectedFavoriteID
        let isDropTarget = project.id == dropTargetID
        let isHovered = project.id == hoveredFavID
        return rowLabel(systemImage: "folder.fill", name: project.name,
                        isSelected: isSelected, isDropTarget: isDropTarget, isHovered: isHovered)
            .contentShape(Rectangle())
            .onTapGesture { onSelectFavorite(project) }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    hoveredFavID = hovering ? project.id : (hoveredFavID == project.id ? nil : hoveredFavID)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                onDropFiles(urls, project, NSEvent.modifierFlags.contains(.option))
                return true
            } isTargeted: { targeted in
                dropTargetID = targeted ? project.id : (dropTargetID == project.id ? nil : dropTargetID)
            }
            .contextMenu {
                Button("Remover dos favoritos", role: .destructive) { vm.remove(project) }
            }
    }

    private func rowLabel(systemImage: String, name: String,
                          isSelected: Bool, isDropTarget: Bool, isHovered: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                // Hierarchical rendering gives folder icons natural visual depth
                // (body lighter than the tab) without adding a second tint.
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(isHovered ? 0.75 : 0.55))
                .frame(width: 16)
            Text(name)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isSelected ? 0.95 : isHovered ? 0.88 : 0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                // Selected rows turn semibold (wider) and can clip a name that fit
                // when regular — scale it down slightly before truncating.
                .minimumScaleFactor(0.82)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(isDropTarget ? Color.accentColor.opacity(0.18)
                    : isSelected ? Color.white.opacity(0.10)
                    : isHovered  ? Color.white.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .opacity(isDropTarget ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.16), value: isDropTarget)
    }

}
