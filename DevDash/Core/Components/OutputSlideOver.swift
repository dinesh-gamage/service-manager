//
//  OutputSlideOver.swift
//  DevDash
//
//  Created by Dinesh Gamage on 2026-02-20.
//

import SwiftUI

struct OutputSlideOver<DataSource: OutputViewDataSource>: View {
    let title: String
    @ObservedObject var dataSource: DataSource
    @Binding var isPresented: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            // Dimmed background
            if isPresented {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isPresented = false
                        }
                    }
                    .transition(.opacity)
            }

            // Slide-over panel
            if isPresented {
                VStack(spacing: 0) {
                    // Header with close button
                    HStack {
                        Text(title)
                            .font(.title3)
                            .fontWeight(.semibold)

                        Spacer()

                        VariantButton(icon: "xmark", variant: .secondary, tooltip: "Close") {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isPresented = false
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(AppTheme.searchBackground)

                    Divider()

                    // Output view
                    CommandOutputView(dataSource: dataSource)
                }
                .frame(width: 700)
                .background(Color(NSColor.windowBackgroundColor))
                .shadow(color: AppTheme.shadowColor.opacity(0.3), radius: 20, x: -5, y: 0)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
    }
}
