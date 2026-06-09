import AppKit

final class LLMStatusView: NSView {
    private var rowStack: NSStackView!

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        rowStack = NSStackView()
        rowStack.orientation = .horizontal
        rowStack.spacing = 12
        rowStack.alignment = .centerY
        addSubview(rowStack)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rowStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            rowStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
        // Show placeholder
        update(models: [])
    }

    func update(models: [LLMEntry]) {
        rowStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard !models.isEmpty else {
            rowStack.addArrangedSubview(makeDot(.systemGray, pulse: false))
            rowStack.addArrangedSubview(makeLabel("No LLM running", dim: true))
            return
        }

        for (i, model) in models.enumerated() {
            if i > 0 {
                let sep = NSTextField(labelWithString: "•")
                sep.textColor = NSColor.white.withAlphaComponent(0.25)
                sep.font = .systemFont(ofSize: 11)
                rowStack.addArrangedSubview(sep)
            }
            rowStack.addArrangedSubview(makeDot(.systemGreen, pulse: true))
            rowStack.addArrangedSubview(makeModelChip(model))
        }
    }

    private func makeModelChip(_ entry: LLMEntry) -> NSView {
        let nameLabel = NSTextField(labelWithString: entry.name)
        nameLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .white
        nameLabel.lineBreakMode = .byTruncatingTail

        let parts = NSStackView(views: [nameLabel])
        parts.orientation = .horizontal
        parts.spacing = 4
        parts.alignment = .centerY

        if !entry.processor.isEmpty {
            let procLabel = NSTextField(labelWithString: "[\(entry.processor)]")
            procLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            procLabel.textColor = processorColor(entry.processor)
            parts.addArrangedSubview(procLabel)
        }
        if !entry.size.isEmpty {
            let sizeLabel = NSTextField(labelWithString: entry.size)
            sizeLabel.font = .systemFont(ofSize: 10)
            sizeLabel.textColor = NSColor.white.withAlphaComponent(0.4)
            parts.addArrangedSubview(sizeLabel)
        }
        return parts
    }

    private func processorColor(_ proc: String) -> NSColor {
        let lo = proc.lowercased()
        if lo.contains("gpu") { return NSColor(red: 0.2, green: 0.9, blue: 0.5, alpha: 1) }
        if lo.contains("cpu") { return NSColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1) }
        return NSColor.white.withAlphaComponent(0.55)
    }

    private func makeDot(_ color: NSColor, pulse: Bool) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = color.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])
        if pulse {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1.0; anim.toValue = 0.3
            anim.duration = 0.8; anim.autoreverses = true
            anim.repeatCount = .infinity
            dot.layer?.add(anim, forKey: "pulse")
        }
        return dot
    }

    private func makeLabel(_ text: String, dim: Bool) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        lbl.textColor = dim ? NSColor.white.withAlphaComponent(0.45) : .white
        return lbl
    }
}
