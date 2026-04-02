import UIKit

final class AutoScrollManager: ObservableObject {
    weak var scrollView: UIScrollView?
    var speed: CGFloat = 0.35
    var didStop: (() -> Void)?

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    func start() {
        guard displayLink == nil, scrollView != nil else { return }
        displayLink = CADisplayLink(target: self, selector: #selector(handleTick))
        lastTimestamp = nil
        displayLink?.add(to: .main, forMode: .common)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        didStop?()
    }

    @objc private func handleTick(_ link: CADisplayLink) {
        guard let scrollView = scrollView else {
            stop()
            return
        }

        if lastTimestamp == nil {
            lastTimestamp = link.timestamp
            return
        }

        let elapsed = link.timestamp - lastTimestamp!
        lastTimestamp = link.timestamp
        let distance = CGFloat(elapsed) * speed * 220

        let maxYOffset = scrollView.contentSize.height - scrollView.bounds.height
        let nextOffset = min(scrollView.contentOffset.y + distance, maxYOffset)

        if nextOffset >= maxYOffset {
            stop()
            return
        }

        let target = CGPoint(x: scrollView.contentOffset.x, y: nextOffset)
        UIView.performWithoutAnimation {
            scrollView.setContentOffset(target, animated: false)
        }
    }
}
