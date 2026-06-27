import SwiftUI

struct SplashScreen: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            Image("ic_launcher_foreground")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
        }
    }

    private var background: Color {
        colorScheme == .dark ? LingoRiseColors.backgroundDark : LingoRiseColors.backgroundLight
    }
}
