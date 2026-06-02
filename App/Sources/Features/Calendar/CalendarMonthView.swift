import SwiftUI
import NautilarrCore

/// A month grid of upcoming releases that fills the screen — each day is a large
/// cell whose posters scale to the available space. Tapping a poster opens its
/// library detail (via the calendar's shared `navigationDestination`).
struct CalendarMonthView: View {
    @ObservedObject var model: CalendarViewModel
    @EnvironmentObject private var instanceStore: InstanceStore
    @State private var month: Date = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()

    private var cal: Calendar { Calendar.current }

    var body: some View {
        let byDay = model.entriesByDay
        VStack(spacing: 10) {
            header
            weekdayHeader
            VStack(spacing: 6) {
                ForEach(weeks.indices, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(Array(weeks[row].enumerated()), id: \.offset) { _, date in
                            if let date {
                                DayCell(date: date,
                                        entries: byDay[cal.startOfDay(for: date)] ?? [],
                                        isToday: cal.isDateInToday(date))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        // Refetch when the displayed month changes (and on first appear) so the
        // grid keeps loading data however far the user navigates.
        .task(id: month) { await model.loadMonth(month, store: instanceStore) }
    }

    private var header: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").font(.title3) }
            Spacer()
            HStack(spacing: 8) {
                Text(month, format: .dateTime.month(.wide).year()).font(.title2.weight(.bold))
                if model.isLoading { ProgressView().controlSize(.small) }
            }
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").font(.title3) }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.shortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(weekdaySymbols, id: \.self) { s in
                Text(s).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Days of the displayed month, padded with leading/trailing blanks.
    private var dayCells: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let start = interval.start
        let daysInMonth = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let weekday = cal.component(.weekday, from: start)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<daysInMonth { cells.append(cal.date(byAdding: .day, value: d, to: start)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var weeks: [[Date?]] {
        stride(from: 0, to: dayCells.count, by: 7).map { Array(dayCells[$0..<min($0 + 7, dayCells.count)]) }
    }

    private func shift(_ months: Int) {
        if let d = cal.date(byAdding: .month, value: months, to: month) {
            month = cal.dateInterval(of: .month, for: d)?.start ?? d
        }
    }
}

private struct DayCell: View {
    let date: Date
    let entries: [CalendarViewModel.Entry]
    let isToday: Bool

    private var dayNumber: Int { Calendar.current.component(.day, from: date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(dayNumber)")
                .font(.subheadline.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.white : .primary)
                .frame(width: 26, height: 26)
                .background { if isToday { Circle().fill(Theme.teal) } }

            if entries.count == 1 {
                // A lone release is centered in the cell.
                CalendarMiniPoster(entry: entries[0])
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if !entries.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    ForEach(entries.prefix(3)) { entry in
                        CalendarMiniPoster(entry: entry)
                    }
                    if entries.count > 3 {
                        Text("+\(entries.count - 3)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
        .glassSurface(in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A poster in the month grid that scales to fill the available cell height.
private struct CalendarMiniPoster: View {
    let entry: CalendarViewModel.Entry
    @EnvironmentObject private var instanceStore: InstanceStore

    var body: some View {
        let poster = image
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(entry.status.color.opacity(0.85), lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        if let media = entry.mediaEntry {
            NavigationLink(value: media) { poster }.buttonStyle(.plain)
        } else {
            poster
        }
    }

    @ViewBuilder
    private var image: some View {
        if let url = PosterURL.resolve(entry.posterURLString, instance: entry.instance) {
            AsyncCachedImage(
                url: url,
                headers: instanceStore.imageHeaders(for: entry.instance),
                allowSelfSignedHosts: entry.instance.allowSelfSignedCertificates
                    ? Set(entry.instance.candidateBaseURLs().compactMap { $0.host }) : []
            )
        } else {
            ZStack { Theme.backgroundGradient; Image(systemName: "film").foregroundStyle(.white.opacity(0.6)) }
        }
    }
}
