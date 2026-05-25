import SwiftUI

struct CompactBlockRow: View {
    let block: ScheduleBlock

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(TimeFormatter.clock(block.startMinute))
                Text(TimeFormatter.clock(block.endMinute))
                    .foregroundStyle(AppTheme.muted)
            }
            .font(.caption.monospacedDigit())
            .frame(width: 48, alignment: .trailing)

            RoundedRectangle(cornerRadius: 3)
                .fill(block.displayCategory.tint)
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(block.title)
                        .font(.subheadline.weight(block.isFree ? .regular : .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                    Spacer()
                    Text(block.durationText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.muted)
                }

                if let note = block.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .background(block.displayCategory.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct DetailedBlockCard: View {
    let block: ScheduleBlock
    let isCurrent: Bool
    var onPlan: ((ScheduleBlock) -> Void)?
    var onDeletePlan: ((ScheduleBlock) -> Void)?

    var body: some View {
        let category = block.displayCategory

        return HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 4)
                .fill(isCurrent ? AppTheme.focus : category.tint)
                .frame(width: 7)

            VStack(alignment: .trailing, spacing: 3) {
                Text(TimeFormatter.clock(block.startMinute))
                    .font(.title3.weight(.bold).monospacedDigit())
                Text(TimeFormatter.clock(block.endMinute))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppTheme.muted)
            }
            .frame(width: 64, alignment: .trailing)

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(block.title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)

                        HStack(spacing: 10) {
                            Label(block.durationText, systemImage: "hourglass")
                            if isCurrent {
                                Label("현재", systemImage: "location.fill")
                                    .foregroundStyle(AppTheme.focus)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    }

                    Spacer()
                    CategoryBadge(category: category)
                }

                if let note = block.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }

                if block.isFree, let onPlan {
                    Button {
                        onPlan(block)
                    } label: {
                        Label("계획하기", systemImage: "plus")
                    }
                    .buttonStyle(ActionPillButtonStyle(tint: AppTheme.accent, isProminent: true))
                    .padding(.top, 2)
                } else if block.isPlanned, let onDeletePlan {
                    Button {
                        onDeletePlan(block)
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                    .buttonStyle(ActionPillButtonStyle(tint: AppTheme.focus))
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .background(isCurrent ? AppTheme.focus.opacity(0.08) : category.surface.opacity(block.isFree ? 0.75 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .decorativeStroke(
            RoundedRectangle(cornerRadius: 8, style: .continuous),
            color: isCurrent ? AppTheme.focus.opacity(0.45) : AppTheme.line
        )
    }
}
