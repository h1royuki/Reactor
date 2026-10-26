import SwiftUI

struct ExploreView: View {
    @State private var query = ""
    @State private var suggestions: [TagSummary] = []
    @State private var trends: [TagSummary] = []
    @State private var weekTop: [TagSummary] = []
    @State private var allTop: [TagSummary] = []
    @State private var loadError: String?
    @Environment(Router.self) private var router

    private var settings: AppSettings { .shared }

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                home
            } else {
                searchResults
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Обзор")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Теги и посты")
        .onSubmit(of: .search) {
            guard !trimmedQuery.isEmpty else { return }
            router.push(.search(trimmedQuery))
        }
        .task(id: trimmedQuery) {
            let current = trimmedQuery
            guard !current.isEmpty else { suggestions = []; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            async let auto = (try? await API.autocomplete(current)) ?? []
            async let found = API.searchTags(current, nsfw: settings.showNSFW)
            var merged: [TagSummary] = []
            var seen = Set<String>()
            let combined = await found + auto
            for tag in combined where !seen.contains(tag.name.lowercased()) {
                if !settings.showNSFW && tag.nsfw == true { continue }
                seen.insert(tag.name.lowercased())
                merged.append(tag)
            }
            guard !Task.isCancelled else { return }
            suggestions = Array(merged.prefix(25))
        }
        .task { await loadHome() }
        .refreshable { await loadHome(force: true) }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var home: some View {
        if let loadError, trends.isEmpty && weekTop.isEmpty {
            ErrorStateView(message: loadError) { Task { await loadHome(force: true) } }
                .listRowBackground(Color.clear)
        }
        if !trends.isEmpty {
            Section("В тренде") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(trends) { tag in
                            NavigationLink(value: Route.tag(tag.name)) {
                                TrendCard(tag: tag)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .listRowInsets(EdgeInsets())
            }
        }
        if !weekTop.isEmpty {
            Section("Популярное за неделю") {
                ForEach(weekTop.prefix(10)) { tag in
                    TagRow(tag: tag)
                }
            }
        }
        if !allTop.isEmpty {
            Section("Больше всего подписчиков") {
                ForEach(allTop.prefix(20)) { tag in
                    TagRow(tag: tag)
                }
            }
        }
        if trends.isEmpty && weekTop.isEmpty && loadError == nil {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        Section {
            NavigationLink(value: Route.search(trimmedQuery)) {
                Label("Искать посты «\(trimmedQuery)»", systemImage: "magnifyingglass")
            }
        }
        if !suggestions.isEmpty {
            Section("Теги") {
                ForEach(suggestions) { tag in
                    TagRow(tag: tag)
                }
            }
        }
    }

    private func loadHome(force: Bool = false) async {
        if !force && !trends.isEmpty { return }
        do {
            async let trendsTask = API.trends()
            async let topTask = API.topTags(nsfw: settings.showNSFW)
            let (t, top) = try await (trendsTask, topTask)
            trends = t.filter { settings.showNSFW || $0.nsfw != true }
            weekTop = top.week.filter { settings.showNSFW || $0.nsfw != true }
            allTop = top.all.filter { settings.showNSFW || $0.nsfw != true }
            loadError = nil
        } catch {
            if !error.isCancellation { loadError = error.localizedDescription }
        }
    }
}

struct TagRow: View {
    let tag: TagSummary

    var body: some View {
        NavigationLink(value: Route.tag(tag.name)) {
            HStack(spacing: 12) {
                AvatarView(url: tag.avatarURL, name: tag.name, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tag.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if tag.nsfw == true {
                            Text("18+")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.red)
                        }
                    }
                    if tag.count > 0 || tag.subscribers > 0 {
                        Text("\(Formatting.compact(tag.count)) постов · \(Formatting.compact(tag.subscribers)) подписчиков")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct TrendCard: View {
    let tag: TagSummary

    var body: some View {
        VStack(spacing: 8) {
            AvatarView(url: tag.avatarURL, name: tag.name, size: 64)
            Text(tag.name)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 84)
        }
    }
}
