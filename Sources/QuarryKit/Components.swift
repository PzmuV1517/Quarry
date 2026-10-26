import AppKit
import SwiftUI

/// A settings page: scrolling, a readable column width, on the backdrop.
public struct PageContainer<Content: View>: View {
    @ViewBuilder var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            content
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
        }
        .background(Backdrop())
        .ferriteStyle()
    }
}

/// A small ? that shows `text` on hover and in a popover on click.
public struct InfoButton: View {
    let text: String
    @State private var isShown = false

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Button { isShown.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(Brand.tertiary)
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading)
                .padding(12)
        }
    }
}

/// A titled group of settings on a glass card.
public struct GlassSection<Content: View>: View {
    let title: String
    var info: String?
    @ViewBuilder var content: Content

    public init(title: String, info: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.info = info
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Brand.tertiary)
                if let info { InfoButton(text: info) }
            }
            .padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .glassCard()
        }
    }
}

/// A settings row: label (with an optional ?) on the left, control on the right.
public struct Row<Control: View>: View {
    let title: String
    var info: String?
    @ViewBuilder var control: Control

    public init(title: String, info: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.info = info
        self.control = control()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 6) {
                Text(title)
                if let info { InfoButton(text: info) }
            }
            Spacer(minLength: 12)
            control
        }
    }
}

/// A sidebar entry. Hand-built instead of a selectable List, whose highlight is always the
/// system accent color; this keeps the sidebar monochrome.
public struct SidebarButton<Icon: View>: View {
    let title: String
    let isSelected: Bool
    var indent: CGFloat
    let action: () -> Void
    @ViewBuilder var icon: Icon
    @State private var isHovered = false

    public init(_ title: String, isSelected: Bool, indent: CGFloat = 0, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.isSelected = isSelected
        self.indent = indent
        self.action = action
        self.icon = icon()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon.frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Brand.primary : Brand.secondary)
            .padding(.leading, 10 + indent)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.12 : isHovered ? 0.05 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.10 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

extension SidebarButton where Icon == Image {
    public init(_ title: String, symbol: String, isSelected: Bool, indent: CGFloat = 0, action: @escaping () -> Void) {
        self.init(title, isSelected: isSelected, indent: indent, action: action) { Image(systemName: symbol) }
    }
}

/// Small caps heading for a group of sidebar entries.
public struct SidebarHeading: View {
    let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(Brand.tertiary)
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }
}

/// An app's icon from its bundle, or Quarry's own.
public struct AppIcon: View {
    let image: NSImage
    let size: CGFloat

    public init(bundle: Bundle = .main, size: CGFloat) {
        image = bundle.image(forResource: "AppIcon") ?? NSWorkspace.shared.icon(forFile: bundle.bundlePath)
        self.size = size
    }

    public var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// A label / value line for About pages, optionally a link.
public struct Fact: View {
    let label: String
    let value: String
    var link: URL?

    public init(_ label: String, _ value: String, link: URL? = nil) {
        self.label = label
        self.value = value
        self.link = link
    }

    public var body: some View {
        HStack {
            Text(label).foregroundStyle(Brand.tertiary).frame(width: 90, alignment: .leading)
            if let link {
                Link(destination: link) {
                    HStack(spacing: 4) {
                        Text(value)
                        Image(systemName: "arrow.up.right").font(.caption2)
                    }
                }
                .foregroundStyle(Brand.primary)
            } else {
                Text(value)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// Who made Quarry and its tools.
public enum Credits {
    public static let author = "Andrei Banu"
    public static let github = "PzmuV1517"
    public static let profile = URL(string: "https://github.com/\(github)")!
    public static let year = "2026"

    public static func repository(_ name: String) -> URL {
        URL(string: "https://github.com/\(github)/\(name)")!
    }
}

/// One release in a version list: tag, date and expandable notes, with an install button.
public struct ReleaseRow: View {
    public enum State: Equatable {
        case installed
        /// Installable; the label is "Install" or "Downgrade".
        case available(String)
        /// Listed but not installable, with a short reason ("TileMyMac", "Standalone only").
        case unavailable(label: String, reason: String)
    }

    let release: Release
    let state: State
    let isBusy: Bool
    let onInstall: () -> Void
    @SwiftUI.State private var isExpanded = false

    public init(release: Release, state: State, isBusy: Bool, onInstall: @escaping () -> Void) {
        self.release = release
        self.state = state
        self.isBusy = isBusy
        self.onInstall = onInstall
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Brand.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text(release.tag).font(.system(size: 14, weight: .bold))
                        if let date = release.date {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(Brand.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                switch state {
                case .installed:
                    Text("Installed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(Brand.hairline))
                case .available(let label):
                    Button(label, action: onInstall)
                        .glassButton()
                        .disabled(isBusy)
                case .unavailable(let label, let reason):
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(Brand.tertiary)
                        .help(reason)
                }
                Link(destination: release.page) {
                    Image(systemName: "arrow.up.right")
                }
                .foregroundStyle(Brand.secondary)
                .help("Open on GitHub")
            }

            if isExpanded {
                Text(Self.notes(release.notes))
                    .font(.callout)
                    .foregroundStyle(Brand.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 18)
            }
        }
    }

    /// GitHub release notes as styled text; headings become bold lines.
    public static func notes(_ markdown: String) -> AttributedString {
        let text = markdown.isEmpty ? "No notes." : markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard line.hasPrefix("#") else { return String(line) }
                return "**" + line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) + "**"
            }
            .joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
