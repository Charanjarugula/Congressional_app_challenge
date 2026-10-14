import SwiftUI

/// The small Apple-Calendar-style tile: white square, red header, today's day number.
struct CalendarIcon: View {
    var size: CGFloat = 40

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: .now))
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(CourtlyColor.red)
                .frame(height: size * 0.275)
            Text(dayNumber)
                .font(CourtlyFont.rounded(size * 0.375))
                .foregroundStyle(CourtlyColor.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}
