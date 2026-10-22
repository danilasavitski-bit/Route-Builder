import UIKit

final class InstructionsViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let viewModel: InstructionsViewModel
    private let store: RouteDraftStore

    private let flow = UICollectionViewFlowLayout()
    private lazy var collectionView: UICollectionView = {
        flow.scrollDirection = .vertical
        flow.minimumLineSpacing = 0
        flow.minimumInteritemSpacing = 0
        let view = UICollectionView(frame: .zero, collectionViewLayout: flow)
        view.dataSource = self
        view.delegate = self
        view.backgroundColor = .clear
        view.isPagingEnabled = false
        view.decelerationRate = .fast
        view.showsVerticalScrollIndicator = false
        view.keyboardDismissMode = .interactive
        view.contentInsetAdjustmentBehavior = .never
        view.register(InstructionCardCell.self, forCellWithReuseIdentifier: InstructionCardCell.reuseID)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let emptyLabel = UILabel()
    private let successScroll = UIScrollView()
    private let successStack = UIStackView()
    private let retryButton = UIButton(type: .system)
    private let finishButton = UIButton(type: .system)
    private let dotStack = UIStackView()
    private var dotHeights: [NSLayoutConstraint] = []
    private var focusedStopID: String?
    private var renderedIDs: [String] = []
    private var renderedStops: [RouteStop] = []
    private var laidOutWidth: CGFloat = 0
    private var heightCache: [String: CGFloat] = [:]
    private let sizingCell = InstructionCardCell(frame: .zero)
    private var cameraStopID: String?

    init(viewModel: InstructionsViewModel, store: RouteDraftStore) {
        self.viewModel = viewModel
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.feed
        addGlow()

        emptyLabel.text = "Select stops before writing instructions."
        emptyLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        emptyLabel.textColor = Theme.secondary
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        successScroll.translatesAutoresizingMaskIntoConstraints = false
        successStack.axis = .vertical
        successStack.spacing = 12
        successStack.translatesAutoresizingMaskIntoConstraints = false
        successScroll.addSubview(successStack)

        retryButton.setTitle("Retry failed alerts", for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.backgroundColor = Theme.teal
        retryButton.layer.cornerRadius = Theme.radius
        retryButton.addTarget(self, action: #selector(retryNoticesTapped), for: .touchUpInside)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.isHidden = true

        finishButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        finishButton.titleLabel?.numberOfLines = 2
        finishButton.titleLabel?.textAlignment = .center
        finishButton.setTitleColor(.white, for: .normal)
        finishButton.backgroundColor = Theme.teal
        finishButton.layer.cornerRadius = Theme.radius
        finishButton.addTarget(self, action: #selector(finishTapped), for: .touchUpInside)
        finishButton.translatesAutoresizingMaskIntoConstraints = false

        dotStack.axis = .vertical
        dotStack.spacing = 6
        dotStack.alignment = .center
        dotStack.isUserInteractionEnabled = false
        dotStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dotStack)

        view.addSubview(collectionView)
        view.addSubview(emptyLabel)
        view.addSubview(successScroll)
        view.addSubview(retryButton)
        view.addSubview(finishButton)

        NSLayoutConstraint.activate([
            dotStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            dotStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: finishButton.topAnchor, constant: -8),

            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            successScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            successScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            successScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            successScroll.bottomAnchor.constraint(equalTo: retryButton.topAnchor, constant: -12),
            successStack.topAnchor.constraint(equalTo: successScroll.contentLayoutGuide.topAnchor),
            successStack.leadingAnchor.constraint(equalTo: successScroll.contentLayoutGuide.leadingAnchor),
            successStack.trailingAnchor.constraint(equalTo: successScroll.contentLayoutGuide.trailingAnchor),
            successStack.bottomAnchor.constraint(equalTo: successScroll.contentLayoutGuide.bottomAnchor),
            successStack.widthAnchor.constraint(equalTo: successScroll.frameLayoutGuide.widthAnchor),

            retryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            retryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            retryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            retryButton.heightAnchor.constraint(equalToConstant: 52),

            finishButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            finishButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            finishButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            finishButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])

        viewModel.onChange = { [weak self] in
            self?.render()
        }
        render()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = collectionView.bounds.width
        guard width > 1 else { return }
        if abs(width - laidOutWidth) > 0.5 {
            laidOutWidth = width
            heightCache.removeAll()
            collectionView.collectionViewLayout.invalidateLayout()
        }
        applyFocus()
    }

    func render() {
        let stops = store.draft.stops
        let ids = stops.map(\.stopID)
        let succeeded: String? = {
            if case .succeeded(let routeID) = viewModel.submitState { return routeID }
            return nil
        }()

        emptyLabel.isHidden = !stops.isEmpty || succeeded != nil
        successScroll.isHidden = succeeded == nil
        collectionView.isHidden = stops.isEmpty || succeeded != nil
        dotStack.isHidden = collectionView.isHidden
        finishButton.isHidden = stops.isEmpty || succeeded != nil
        rebuildDots(count: collectionView.isHidden ? 0 : stops.count)
        if let succeeded {
            rebuildSuccess(routeID: succeeded)
        } else {
            retryButton.isHidden = true
        }

        switch viewModel.submitState {
        case .idle:
            finishButton.setTitle("Finish instructions", for: .normal)
            finishButton.backgroundColor = Theme.teal
            finishButton.isEnabled = true
        case .sending:
            finishButton.setTitle("Sending…", for: .normal)
            finishButton.backgroundColor = Theme.teal
            finishButton.isEnabled = false
        case .failed(let message):
            finishButton.setTitle(message, for: .normal)
            finishButton.backgroundColor = Theme.danger
            finishButton.isEnabled = true
        case .succeeded:
            break
        }

        if ids != renderedIDs {
            let page = min(nearestIndex(), max(0, ids.count - 1))
            renderedIDs = ids
            renderedStops = stops
            heightCache.removeAll()
            collectionView.reloadData()
            collectionView.layoutIfNeeded()
            align(to: page, animated: false)
        } else {
            renderedStops = stops
            for case let cell as InstructionCardCell in collectionView.visibleCells {
                guard let stop = stops.first(where: { $0.stopID == cell.stopID }) else { continue }
                cell.configure(stop: stop, invalid: viewModel.invalidStopIDs.contains(cell.stopID))
                cell.showDeliveryPhotos(viewModel.photos[stop.stopID], local: stop.stopID.hasPrefix("local_"))
                cell.loadImage = { [weak self] url in
                    await self?.viewModel.imageData(for: url)
                }
                cell.showDropOff(path: stop.dropOffPhotoPath)
            }
            collectionView.collectionViewLayout.invalidateLayout()
        }

        if let identifier = viewModel.consumeScrollRequest(),
           let row = stops.firstIndex(where: { $0.stopID == identifier }) {
            align(to: row, animated: true)
        }
        applyFocus()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        applyFocus()
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        let count = store.draft.stops.count
        guard count > 1, collectionView.bounds.height > 1 else { return }
        let proposed = targetContentOffset.pointee.y
        let lookAhead = proposed + velocity.y * 120
        var frames: [CGRect] = []
        for item in 0..<count {
            guard let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: item, section: 0))?.frame else { continue }
            frames.append(frame)
        }
        guard let card = frames.min(by: { abs($0.minY - lookAhead) < abs($1.minY - lookAhead) }) else { return }
        if card.height > collectionView.bounds.height, proposed >= card.minY, proposed <= card.maxY - collectionView.bounds.height {
            return
        }
        let maxOffset = max(0, collectionView.contentSize.height - collectionView.bounds.height)
        targetContentOffset.pointee.y = min(max(0, card.minY), maxOffset)
    }

    private func nearestIndex() -> Int {
        let count = store.draft.stops.count
        guard count > 0, collectionView.bounds.height > 1 else { return 0 }
        let offset = collectionView.contentOffset.y
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for item in 0..<count {
            guard let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: item, section: 0))?.frame else { continue }
            let distance = abs(frame.minY - offset)
            if distance < bestDistance {
                bestDistance = distance
                best = item
            }
        }
        return best
    }

    private func align(to page: Int, animated: Bool) {
        guard store.draft.stops.indices.contains(page) else { return }
        collectionView.layoutIfNeeded()
        guard let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: page, section: 0))?.frame else { return }
        let maxOffset = max(0, collectionView.contentSize.height - collectionView.bounds.height)
        let offset = min(max(0, frame.minY), maxOffset)
        collectionView.setContentOffset(CGPoint(x: 0, y: offset), animated: animated)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = collectionView.bounds.width
        guard width > 1, renderedStops.indices.contains(indexPath.item) else {
            return CGSize(width: max(width, 1), height: 1)
        }
        let stop = renderedStops[indexPath.item]
        let key = [
            stop.stopID,
            stop.instructions,
            viewModel.invalidStopIDs.contains(stop.stopID) ? "invalid" : "valid",
            stop.stopID.hasPrefix("local_") ? "local" : "remote",
            stop.dropOffPhotoPath == nil ? "nophoto" : "photo",
            String(format: "%.0f", width)
        ].joined(separator: "|")
        if let cached = heightCache[key] {
            return CGSize(width: width, height: cached)
        }
        sizingCell.configure(stop: stop, invalid: viewModel.invalidStopIDs.contains(stop.stopID))
        sizingCell.showDeliveryPhotos(stop.stopID.hasPrefix("local_") ? nil : .ready([]), local: stop.stopID.hasPrefix("local_"))
        sizingCell.loadImage = nil
        sizingCell.showDropOff(path: stop.dropOffPhotoPath)
        let height = sizingCell.measuredHeight(width: width)
        heightCache[key] = height
        return CGSize(width: width, height: height)
    }

    private func applyFocus() {
        guard !collectionView.isHidden else { return }
        let viewport = collectionView.bounds
        let cells = collectionView.visibleCells.compactMap { $0 as? InstructionCardCell }
        guard !cells.isEmpty else { return }

        func visibleFraction(of cell: InstructionCardCell) -> CGFloat {
            let height = cell.bounds.height
            guard height > 1 else { return 0 }
            return cell.frame.intersection(viewport).height / height
        }

        let winner = cells.max { lhs, rhs in
            let left = visibleFraction(of: lhs)
            let right = visibleFraction(of: rhs)
            if abs(left - right) > 0.001 {
                return left < right
            }
            return lhs.stopID != focusedStopID
        }
        guard let winner else { return }
        focusedStopID = winner.stopID
        for cell in cells {
            cell.setActive(cell === winner)
        }
        if let item = collectionView.indexPath(for: winner)?.item {
            updateDots(active: item)
        }
    }

    private func rebuildDots(count: Int) {
        guard dotStack.arrangedSubviews.count != count else { return }
        dotStack.arrangedSubviews.forEach { view in
            dotStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        dotHeights.removeAll()
        for _ in 0..<count {
            let dot = UIView()
            dot.backgroundColor = Theme.dot
            dot.layer.cornerRadius = 2.5
            dot.translatesAutoresizingMaskIntoConstraints = false
            let height = dot.heightAnchor.constraint(equalToConstant: 5)
            dotHeights.append(height)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 5),
                height
            ])
            dotStack.addArrangedSubview(dot)
        }
    }

    private func updateDots(active: Int) {
        for (index, height) in dotHeights.enumerated() {
            let on = index == active
            height.constant = on ? 16 : 5
            dotStack.arrangedSubviews[index].backgroundColor = on ? Theme.teal : Theme.dot
        }
    }

    private func addGlow() {
        let top = UIView()
        top.backgroundColor = Theme.teal.withAlphaComponent(0.10)
        top.layer.cornerRadius = 150
        top.isUserInteractionEnabled = false
        top.translatesAutoresizingMaskIntoConstraints = false
        let bottom = UIView()
        bottom.backgroundColor = Theme.teal.withAlphaComponent(0.10)
        bottom.layer.cornerRadius = 110
        bottom.isUserInteractionEnabled = false
        bottom.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(top)
        view.addSubview(bottom)
        NSLayoutConstraint.activate([
            top.widthAnchor.constraint(equalToConstant: 300),
            top.heightAnchor.constraint(equalToConstant: 300),
            top.topAnchor.constraint(equalTo: view.topAnchor, constant: -150),
            top.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 90),
            bottom.widthAnchor.constraint(equalToConstant: 220),
            bottom.heightAnchor.constraint(equalToConstant: 220),
            bottom.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 110),
            bottom.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -70)
        ])
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        renderedStops.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: InstructionCardCell.reuseID, for: indexPath) as! InstructionCardCell
        guard renderedStops.indices.contains(indexPath.item) else { return cell }
        let stop = renderedStops[indexPath.item]
        cell.configure(stop: stop, invalid: viewModel.invalidStopIDs.contains(stop.stopID))
        cell.showDeliveryPhotos(viewModel.photos[stop.stopID], local: stop.stopID.hasPrefix("local_"))
        cell.loadImage = { [weak self] url in
            await self?.viewModel.imageData(for: url)
        }
        cell.showDropOff(path: stop.dropOffPhotoPath)
        viewModel.loadPhotosIfNeeded(stopID: stop.stopID)
        cell.onCamera = { [weak self] in
            self?.openCamera(for: stop.stopID)
        }
        cell.onTextChange = { [weak self] text in
            self?.viewModel.instructionsChanged(stopID: stop.stopID, text: text)
        }
        cell.onClear = { [weak self] in
            self?.viewModel.clear(stopID: stop.stopID)
        }
        cell.onRemove = { [weak self] in
            self?.viewModel.remove(stopID: stop.stopID)
        }
        return cell
    }

    @objc private func finishTapped() {
        Task { await viewModel.finish() }
    }

    @objc private func retryNoticesTapped() {
        Task { await viewModel.retryFailedNotices() }
    }

    private func rebuildSuccess(routeID: String) {
        successStack.arrangedSubviews.forEach { view in
            successStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let title = UILabel()
        title.text = "Route \(routeID) sent."
        title.font = .systemFont(ofSize: 22, weight: .heavy)
        title.textColor = Theme.text
        title.numberOfLines = 0
        successStack.addArrangedSubview(title)

        let heading = UILabel()
        heading.text = "Driver alerts"
        heading.font = .systemFont(ofSize: 15, weight: .bold)
        heading.textColor = Theme.secondary
        successStack.addArrangedSubview(heading)

        for notice in viewModel.notices {
            let line = UILabel()
            line.numberOfLines = 0
            line.font = .systemFont(ofSize: 16, weight: .semibold)
            switch notice.status {
            case "sent":
                line.text = "\(notice.name) — Sent"
                line.textColor = Theme.teal
            case "failed":
                let reason = notice.reason?.replacingOccurrences(of: "_", with: " ")
                line.text = "\(notice.name) — Failed" + (reason.map { " (\($0))" } ?? "")
                line.textColor = Theme.danger
            default:
                line.text = "\(notice.name) — Sending…"
                line.textColor = Theme.text
            }
            successStack.addArrangedSubview(line)
        }
        let failed = viewModel.notices.contains { $0.status == "failed" }
        let stillSending = viewModel.notices.contains { $0.status == "sending" }
        retryButton.isHidden = !failed || stillSending
    }

    private func openCamera(for stopID: String) {
        cameraStopID = stopID
        let source: UIImagePickerController.SourceType
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            source = .camera
        } else if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            source = .photoLibrary
        } else {
            let alert = UIAlertController(
                title: "No camera",
                message: "This device cannot take a drop-off photo.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = self
        present(picker, animated: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = info[.originalImage] as? UIImage
        let stopID = cameraStopID
        picker.dismiss(animated: true) { [weak self] in
            guard let self, let image, let stopID else { return }
            guard let path = try? DropOffPhotoStore.save(image, stopID: stopID) else { return }
            self.viewModel.attachDropOffPhoto(stopID: stopID, path: path)
        }
    }
}
