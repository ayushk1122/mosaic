import SwiftUI

/// Left-aligned birthday control: shows `MMM d, yyyy`, and reveals a wheel picker on tap.
struct MosaicBirthdayPicker: View {
    @Binding var date: Date
    var labelColor: Color = MosaicBrand.inkBlack
    var fieldBackground: Color? = Color.white
    var accessibilityIdentifier: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(MosaicSettingsList.birthdayLabel(date))
                        .font(.body.weight(.medium))
                        .foregroundStyle(labelColor)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(labelColor.opacity(0.45))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(fieldBackground ?? Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    if fieldBackground != nil {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(labelColor.opacity(0.12), lineWidth: 1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(accessibilityIdentifier).value")
            .accessibilityHint(isExpanded ? "Hides the date picker" : "Shows the date picker")

            if isExpanded {
                DatePicker(
                    "Birthday",
                    selection: $date,
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(accessibilityIdentifier)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
