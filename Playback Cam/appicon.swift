import SwiftUI

struct AppIconView: View {
    var body: some View {
        ZStack {
            AppIconBackground()

            ZStack {
                AppIconShutterRing()
                    .frame(width: 624, height: 624)

                RoundedRectangle(cornerRadius: 248, style: .continuous)
                    .fill(.red)
                    .frame(width: 448, height: 448)

                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 224, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
                    .offset(y: -16)
                    .opacity(0.8)
            }
            .frame(width: 784, height: 784)
            .shadow(color: .black.opacity(0.24), radius: 80, y: 48)
        }
    }
}

private struct AppIconBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 230 / 255, green: 230 / 255, blue: 230 / 255),
                    Color(red: 120 / 255, green: 120 / 255, blue: 120 / 255)
                ],
                startPoint: .topTrailing,
                endPoint: .bottom
            )
        }
    }
}

private struct AppIconShutterRing: View {
    private let stripeCount = 112

    var body: some View {
        ZStack {
            ForEach(0..<stripeCount, id: \.self) { index in
                Rectangle()
                    .fill(.white)
                    .frame(width: 8, height: 32)
                    .offset(y: -256)
                    .rotationEffect(.degrees(Double(index) * (360.0 / Double(stripeCount))))
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 32, y: 16)
    }
}

struct AppIconView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AppIconView()
                .frame(width: 1024, height: 1024)
                .previewDisplayName("1024")

            AppIconView()
                .frame(width: 240, height: 240)
                .padding()
                .background(Color.black)
                .previewLayout(.sizeThatFits)
                .previewDisplayName("Fitted")
        }
    }
}
