import AppKit

/// One row in the history list: type icon / thumbnail, preview text,
/// source + time, and pin/delete buttons.
final class ClipboardItemRow: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("ClipboardItemRow")
    static let rowHeight: CGFloat = 54

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let pinButton = NSButton()
    private let deleteButton = NSButton()

    private var item: ClipboardItem?

    var onTogglePin: ((ClipboardItem) -> Void)?
    var onDelete: ((ClipboardItem) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        identifier = Self.reuseIdentifier

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 4
        iconView.layer?.masksToBounds = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1

        configureIconButton(pinButton, symbol: "pin", action: #selector(pinTapped))
        configureIconButton(deleteButton, symbol: "trash", action: #selector(deleteTapped))

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(pinButton)
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 24),
            deleteButton.heightAnchor.constraint(equalToConstant: 24),

            pinButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -4),
            pinButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 24),
            pinButton.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: pinButton.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: pinButton.leadingAnchor, constant: -8),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2)
        ])
    }

    private func configureIconButton(_ button: NSButton, symbol: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)
        button.target = self
        button.action = action
    }

    func configure(with item: ClipboardItem) {
        self.item = item

        titleLabel.stringValue = item.preview
            .replacingOccurrences(of: "\n", with: " ⏎ ")

        var subtitleParts: [String] = []
        if let sourceApp = item.sourceApp, !sourceApp.isEmpty {
            subtitleParts.append(sourceApp)
        }
        subtitleParts.append(DateFormatting.relative(item.updatedAt))
        if !item.tags.isEmpty {
            subtitleParts.append(item.tags.map { "#\($0)" }.joined(separator: " "))
        }
        subtitleLabel.stringValue = subtitleParts.joined(separator: " • ")

        if item.type == .image,
           let data = FileStorage.loadData(atPath: item.filePath),
           let thumbnail = NSImage(data: data) {
            iconView.image = thumbnail
            iconView.contentTintColor = nil
        } else {
            iconView.image = NSImage(
                systemSymbolName: item.type.symbolName,
                accessibilityDescription: item.type.displayName
            )
            iconView.contentTintColor = .secondaryLabelColor
        }

        let pinSymbol = item.isPinned ? "pin.fill" : "pin"
        pinButton.image = NSImage(systemSymbolName: pinSymbol, accessibilityDescription: "Pin")
        pinButton.contentTintColor = item.isPinned ? .controlAccentColor : .secondaryLabelColor
        deleteButton.contentTintColor = .secondaryLabelColor
    }

    @objc private func pinTapped() {
        guard let item = item else { return }
        onTogglePin?(item)
    }

    @objc private func deleteTapped() {
        guard let item = item else { return }
        onDelete?(item)
    }
}
