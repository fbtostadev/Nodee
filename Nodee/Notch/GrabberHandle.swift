//
//  GrabberHandle.swift
//  Nodee
//
//  The bottom handle that condenses the expanded panel back to the Notch.
//  Mirrors the macOS / iOS bottom-sheet grabber: hover highlights it, an upward
//  click-drag pulls the panel home, and a click is the no-trackpad fallback.
//  A two- or three-finger swipe up while hovering it also condenses — that part
//  is read as raw multitouch in `NotchGestureView`, gated on the hover state
//  this view publishes. Living at the panel's bottom edge keeps every one of
//  these clear of the canvas pan and the system's own multi-finger gestures.
//

import SwiftUI

struct GrabberHandle: View {
    @Environment(PanelPresentation.self) private var presentation
    @State private var isHovering = false

    var body: some View {
        let active = isHovering || presentation.grabberDragProgress > 0

        ZStack {
            // Generous invisible hit area for comfortable hover + drag.
            Color.clear
                .frame(width: Theme.grabberWidth + 96, height: Theme.grabberHitHeight)
                .contentShape(Rectangle())

            Capsule()
                .fill(.white.opacity(active ? 0.55 : 0.22))
                .frame(width: Theme.grabberWidth, height: Theme.grabberHeight)
                // Lift slightly toward the Notch as the drag progresses.
                .offset(y: -presentation.grabberDragProgress * 6)
                .scaleEffect(active ? 1.06 : 1, anchor: .center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Theme.grabberBottomInset)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: active)
        .onHover { hovering in
            isHovering = hovering
            presentation.isHoveringGrabber = hovering
        }
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let up = max(0, -value.translation.height)
                    presentation.grabberDragProgress = min(up / Theme.grabberDragCommit, 1)
                }
                .onEnded { value in
                    let committed = -value.translation.height > Theme.grabberDragCommit
                    presentation.grabberDragProgress = 0
                    // Released past the threshold = intent; short of it = cancel.
                    if committed { presentation.requestCondense() }
                }
        )
        .onTapGesture { presentation.requestCondense() }
        .help("Recolher para o Notch")
        .accessibilityLabel("Recolher para o Notch")
        .accessibilityAddTraits(.isButton)
    }
}
