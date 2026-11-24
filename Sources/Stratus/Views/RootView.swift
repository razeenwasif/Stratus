import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        ZStack {
            T3.bg.ignoresSafeArea()
            WindowAccessor()

            HStack(spacing: 0) {
                if !appState.sidebarCollapsed {
                    SidebarView()
                        .frame(width: 224)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                mainWorkspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(T3.bg)

                if let selection = appState.inspector {
                    InspectorDrawerView(selection: selection)
                        .frame(width: 360)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            if appState.showCommandPalette {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { appState.showCommandPalette = false }

                CommandPaletteView()
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if let toast = appState.toastMessage {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ToastBanner(message: toast, isError: appState.toastIsError)
                    }
                }
                .padding(24)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: appState.showCommandPalette)
        .animation(.easeOut(duration: 0.18), value: appState.inspector != nil)
        .animation(.easeOut(duration: 0.16), value: appState.toastMessage)
        .sheet(isPresented: $state.showAuthSheet) {
            AuthSettingsSheet()
                .environment(appState)
        }
        .task {
            await appState.bootstrap()
        }
        .onKeyPress(.escape) {
            if appState.showCommandPalette {
                appState.showCommandPalette = false
                return .handled
            }
            if appState.inspector != nil {
                appState.inspector = nil
                return .handled
            }
            return .ignored
        }
    }

    @ViewBuilder
    private var mainWorkspace: some View {
        switch appState.selectedSection {
        case .overview:
            OverviewView()
        case .compute:
            ComputeView()
        case .cloudRun:
            CloudRunView()
        case .storage:
            StorageView()
        case .dataServices:
            DataServicesView()
        case .logging:
            LoggingView()
        case .iamAndApis:
            IAMAndAPIsView()
        }
    }
}
