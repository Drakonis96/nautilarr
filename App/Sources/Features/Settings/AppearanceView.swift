import SwiftUI

/// Accent colour, light/dark mode and tab ordering.
struct AppearanceView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.horizontalSizeClass) private var hSize

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]

    /// On iPhone, the first four *visible* sections live in the bottom tab bar;
    /// the rest fold into the "More" tab. Mirror `CompactRootView`'s split so the
    /// Appearance list can show which is which.
    private var tabBarSet: Set<AppDestination> {
        let visible = settings.visibleTabOrder
        return Set(visible.count > 5 ? Array(visible.prefix(4)) : visible)
    }

    var body: some View {
        Form {
            Section("Accent Color") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(AccentPalette.allCases) { palette in
                        Circle()
                            .fill(palette.color)
                            .frame(width: 36, height: 36)
                            .overlay {
                                if palette == settings.accent {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay(Circle().strokeBorder(Color.hairline))
                            .onTapGesture { settings.accent = palette }
                            .accessibilityLabel(palette.label)
                    }
                }
                .padding(.vertical, 4)
            }
            .tintedCards()

            Section {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(BackgroundPalette.allCases) { palette in
                        backgroundSwatch(palette)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Background Color")
            } footer: {
                Text("A solid colour fills the background while the cards stay light — just like the grey “System” default, but in your colour.")
            }
            .tintedCards()

            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { settings.colorScheme },
                    set: { settings.colorScheme = $0 }
                )) {
                    ForEach(AppColorScheme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .tintedCards()

            Section {
                Picker("App Language", selection: Binding(
                    get: { settings.appLanguage },
                    set: { settings.appLanguage = $0 }
                )) {
                    Text("System").tag("")
                    Text("English").tag("en")
                    Text("Español").tag("es")
                    Text("Français").tag("fr")
                    Text("Deutsch").tag("de")
                }
            } header: {
                Text("Language")
            } footer: {
                Text("The language changes immediately across the app.")
            }
            .tintedCards()

            Section {
                Picker("Text Size", selection: Binding(
                    get: { settings.textSize },
                    set: { settings.textSize = $0 }
                )) {
                    ForEach(AppTextSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("The quick brown fox jumps over the lazy dog.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Text Size")
            } footer: {
                Text("Scales text throughout the app. The sample above previews the current size.")
            }
            .tintedCards()

            Section {
                ForEach(settings.reorderableTabOrder) { destination in
                    HStack(spacing: 10) {
                        Label {
                            Text(destination.title)
                        } icon: {
                            if let shortcut = destination.mediaShortcut {
                                Image(shortcut.logoAssetName).resizable().scaledToFit().frame(width: 20, height: 20)
                            } else {
                                Image(systemName: destination.symbol)
                            }
                        }
                        .foregroundStyle(settings.isHidden(destination) ? .secondary : .primary)
                        Spacer()
                        // iPhone only: show whether this section lands in the tab
                        // bar or under "More" so reordering is predictable.
                        if hSize == .compact, !settings.isHidden(destination) {
                            placementBadge(inTabBar: tabBarSet.contains(destination))
                        }
                        if destination.canHide {
                            Button {
                                settings.toggleHidden(destination)
                            } label: {
                                Image(systemName: settings.isHidden(destination) ? "eye.slash" : "eye")
                                    .foregroundStyle(settings.isHidden(destination) ? Color.secondary : Color.accentColor)
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Image(systemName: "lock")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        // Visible drag affordance so it's obvious rows can be
                        // reordered (the row is draggable in Edit mode).
                        Image(systemName: "line.3.horizontal")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Drag to reorder")
                    }
                }
                .onMove { from, to in
                    var order = settings.reorderableTabOrder
                    order.move(fromOffsets: from, toOffset: to)
                    settings.applyReorder(order)
                }
            } header: {
                HStack {
                    Text("Navigation")
                    Spacer()
                    Label("Drag to reorder", systemImage: "arrow.up.arrow.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            } footer: {
                Text("Tap “Edit” (top-right), then drag the ☰ handle to reorder. On iPhone the first four visible sections appear in the bottom tab bar; the rest fold into “More”. Tap the eye to hide a section. Home and Settings always stay visible.")
            }
            .tintedCards()

            Section {
                Toggle(isOn: Binding(
                    get: { settings.scrollToTopEnabled },
                    set: { settings.scrollToTopEnabled = $0 }
                )) {
                    Label("Scroll-to-top button", systemImage: "arrow.up.to.line")
                }
            } header: {
                Text("Navigation Aids")
            } footer: {
                Text("Shows a floating button in the bottom-left corner of every screen that jumps back to the top.")
            }
            .tintedCards()

            Section {
                NavigationLink {
                    ShortcutsSettingsView()
                } label: {
                    Label("Plex / Jellyfin shortcuts", systemImage: "play.rectangle.on.rectangle")
                }
            }
            .tintedCards()
        }
        .navigationTitle("Appearance")
        .toolbar { EditButton() }
    }

    @ViewBuilder
    private func backgroundSwatch(_ palette: BackgroundPalette) -> some View {
        let selected = palette == settings.background
        Circle()
            .fill(swatchFill(palette))
            .frame(width: 36, height: 36)
            .overlay {
                if palette == .system {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(palette == .system ? Color.primary : .white)
                }
            }
            .overlay(Circle().strokeBorder(selected ? Color.accentColor : Color.hairline, lineWidth: selected ? 2 : 1))
            .onTapGesture { settings.background = palette }
            .accessibilityLabel(palette.label)
    }

    private func swatchFill(_ palette: BackgroundPalette) -> Color {
        palette.pastel ?? Color(uiColor: .secondarySystemBackground)
    }

    private func placementBadge(inTabBar: Bool) -> some View {
        Text(inTabBar ? "Tab bar" : "More")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(inTabBar ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background((inTabBar ? Color.accentColor : Color.secondary).opacity(0.15), in: Capsule())
    }
}
