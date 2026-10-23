import UIKit

final class DepotViewController: UIViewController, RouteDraftListener {
    private let store = RouteDraftStore()
    private let api = APIClient.live()
    private let stopsViewModel: StopsViewModel
    private let instructionsViewModel: InstructionsViewModel
    private let stopsController: StopsViewController
    private let instructionsController: InstructionsViewController

    private let subtitleLabel = UILabel()
    private let stopsTab = TabButton(title: "Stops")
    private let instructionsTab = TabButton(title: "Instructions")
    private let container = UIView()
    private var showingStops = true

    init() {
        stopsViewModel = StopsViewModel(api: api, store: store)
        instructionsViewModel = InstructionsViewModel(api: api, store: store)
        stopsController = StopsViewController(viewModel: stopsViewModel, store: store, onContinue: {})
        instructionsController = InstructionsViewController(viewModel: instructionsViewModel, store: store)
        super.init(nibName: nil, bundle: nil)
        stopsController.onContinue = { [weak self] in
            self?.showStops(false)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        let header = buildHeader()
        embed(stopsController)
        embed(instructionsController)
        store.addListener(self)
        subtitleLabel.text = store.draft.subtitle
        showStops(true)
    }

    private func buildHeader() -> UIView {
        let mark = UIView()
        mark.backgroundColor = Theme.teal
        mark.layer.cornerRadius = Theme.markRadius
        mark.translatesAutoresizingMaskIntoConstraints = false
        let ring = UIView()
        ring.layer.borderColor = UIColor.white.cgColor
        ring.layer.borderWidth = 2
        ring.layer.cornerRadius = 9
        ring.translatesAutoresizingMaskIntoConstraints = false
        let dot = UIView()
        dot.backgroundColor = .white
        dot.layer.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false
        mark.addSubview(ring)
        mark.addSubview(dot)

        let title = UILabel()
        title.text = "Morning route — Central area"
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.8
        title.font = Theme.titleFont()
        title.textColor = Theme.text
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = Theme.secondary
        let titles = UIStackView(arrangedSubviews: [title, subtitleLabel])
        titles.axis = .vertical
        titles.spacing = 0
        titles.translatesAutoresizingMaskIntoConstraints = false

        let header = UIView()
        header.backgroundColor = Theme.card
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(mark)
        header.addSubview(titles)

        let tabs = UIView()
        tabs.backgroundColor = Theme.card
        tabs.translatesAutoresizingMaskIntoConstraints = false
        let tabRow = UIStackView(arrangedSubviews: [stopsTab, instructionsTab])
        tabRow.axis = .horizontal
        tabRow.distribution = .fillEqually
        tabRow.translatesAutoresizingMaskIntoConstraints = false
        tabs.addSubview(tabRow)
        let hairline = UIView()
        hairline.backgroundColor = Theme.hairline
        hairline.translatesAutoresizingMaskIntoConstraints = false
        tabs.addSubview(hairline)

        stopsTab.addTarget(self, action: #selector(stopsTapped), for: .touchUpInside)
        instructionsTab.addTarget(self, action: #selector(instructionsTapped), for: .touchUpInside)

        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        view.addSubview(tabs)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mark.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            mark.topAnchor.constraint(equalTo: header.safeAreaLayoutGuide.topAnchor, constant: 8),
            mark.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -12),
            mark.widthAnchor.constraint(equalToConstant: 44),
            mark.heightAnchor.constraint(equalToConstant: 44),
            ring.centerXAnchor.constraint(equalTo: mark.centerXAnchor),
            ring.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
            ring.widthAnchor.constraint(equalToConstant: 18),
            ring.heightAnchor.constraint(equalToConstant: 18),
            dot.centerXAnchor.constraint(equalTo: mark.centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            titles.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 12),
            titles.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            titles.centerYAnchor.constraint(equalTo: mark.centerYAnchor),

            tabs.topAnchor.constraint(equalTo: header.bottomAnchor),
            tabs.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabs.heightAnchor.constraint(equalToConstant: 46),
            tabRow.topAnchor.constraint(equalTo: tabs.topAnchor),
            tabRow.leadingAnchor.constraint(equalTo: tabs.leadingAnchor),
            tabRow.trailingAnchor.constraint(equalTo: tabs.trailingAnchor),
            tabRow.bottomAnchor.constraint(equalTo: tabs.bottomAnchor),
            hairline.leadingAnchor.constraint(equalTo: tabs.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: tabs.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: tabs.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            container.topAnchor.constraint(equalTo: tabs.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        return header
    }

    private func embed(_ controller: UIViewController) {
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: container.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        controller.didMove(toParent: self)
    }

    private func showStops(_ stops: Bool) {
        showingStops = stops
        stopsController.view.isHidden = !stops
        instructionsController.view.isHidden = stops
        stopsTab.setSelected(stops)
        instructionsTab.setSelected(!stops)
        if !stops {
            instructionsController.render()
        }
    }

    func routeDraftDidChange(_ draft: RouteDraft) {
        subtitleLabel.text = draft.subtitle
        instructionsViewModel.draftChanged()
    }

    @objc private func stopsTapped() {
        showStops(true)
    }

    @objc private func instructionsTapped() {
        showStops(false)
    }
}

private final class TabButton: UIControl {
    private let label = UILabel()
    private let underline = UIView()

    init(title: String) {
        super.init(frame: .zero)
        label.text = title
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        underline.backgroundColor = Theme.teal
        underline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addSubview(underline)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            underline.leadingAnchor.constraint(equalTo: leadingAnchor),
            underline.trailingAnchor.constraint(equalTo: trailingAnchor),
            underline.bottomAnchor.constraint(equalTo: bottomAnchor),
            underline.heightAnchor.constraint(equalToConstant: 3)
        ])
        setSelected(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setSelected(_ selected: Bool) {
        label.font = Theme.tabFont(selected: selected)
        label.textColor = selected ? Theme.teal : Theme.secondary
        underline.isHidden = !selected
    }
}
