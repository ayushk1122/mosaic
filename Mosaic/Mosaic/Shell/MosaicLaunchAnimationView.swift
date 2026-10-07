import SwiftUI

struct MosaicLaunchAnimationView: View {
    var onFinished: () -> Void

    @State private var revealProgress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let wordmarkWidth = min(geometry.size.width * 0.74, 340)
            let wordmarkHeight = wordmarkWidth * (404.0 / 1024.0)

            ZStack {
                MosaicBrand.cream.ignoresSafeArea()

                Image("MosaicWordmark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(MosaicBrand.inkBlack)
                    .frame(width: wordmarkWidth, height: wordmarkHeight)
                    .mask {
                        MosaicWordmarkWritingPath()
                            .trim(from: 0, to: revealProgress)
                            .stroke(
                                MosaicBrand.inkBlack,
                                style: StrokeStyle(
                                    lineWidth: wordmarkHeight * 0.95,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .frame(width: wordmarkWidth, height: wordmarkHeight)
                    }
                    .accessibilityIdentifier("launch.wordmark")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("launch.screen")
        .task {
            if reduceMotion {
                revealProgress = 1
                try? await Task.sleep(for: .milliseconds(350))
            } else {
                withAnimation(.easeInOut(duration: 2.1)) {
                    revealProgress = 1
                }
                try? await Task.sleep(for: .milliseconds(2400))
            }
            onFinished()
        }
    }
}

/// Approximates a single cursive stroke through the Mosaic wordmark for a writing reveal.
private struct MosaicWordmarkWritingPath: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        var path = Path()
        path.move(to: CGPoint(x: 0.03 * w, y: 0.84 * h))
        path.addCurve(
            to: CGPoint(x: 0.17 * w, y: 0.18 * h),
            control1: CGPoint(x: -0.02 * w, y: 0.42 * h),
            control2: CGPoint(x: 0.10 * w, y: 0.06 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.27 * w, y: 0.80 * h),
            control1: CGPoint(x: 0.22 * w, y: 0.48 * h),
            control2: CGPoint(x: 0.24 * w, y: 0.70 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.34 * w, y: 0.34 * h),
            control1: CGPoint(x: 0.29 * w, y: 0.66 * h),
            control2: CGPoint(x: 0.31 * w, y: 0.42 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.44 * w, y: 0.72 * h),
            control1: CGPoint(x: 0.37 * w, y: 0.52 * h),
            control2: CGPoint(x: 0.40 * w, y: 0.66 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.52 * w, y: 0.40 * h),
            control1: CGPoint(x: 0.47 * w, y: 0.58 * h),
            control2: CGPoint(x: 0.49 * w, y: 0.46 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.60 * w, y: 0.68 * h),
            control1: CGPoint(x: 0.55 * w, y: 0.50 * h),
            control2: CGPoint(x: 0.57 * w, y: 0.62 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.67 * w, y: 0.36 * h),
            control1: CGPoint(x: 0.62 * w, y: 0.54 * h),
            control2: CGPoint(x: 0.64 * w, y: 0.42 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.73 * w, y: 0.58 * h),
            control1: CGPoint(x: 0.69 * w, y: 0.44 * h),
            control2: CGPoint(x: 0.71 * w, y: 0.52 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.82 * w, y: 0.46 * h),
            control1: CGPoint(x: 0.76 * w, y: 0.56 * h),
            control2: CGPoint(x: 0.78 * w, y: 0.48 * h)
        )
        path.addCurve(
            to: CGPoint(x: 0.97 * w, y: 0.52 * h),
            control1: CGPoint(x: 0.88 * w, y: 0.42 * h),
            control2: CGPoint(x: 0.93 * w, y: 0.56 * h)
        )
        return path
    }
}

#Preview {
    MosaicLaunchAnimationView(onFinished: {})
}
