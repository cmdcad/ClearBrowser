import UIKit

final class AutoScrollManager: ObservableObject {
    weak var scrollView: UIScrollView?
    var speed: CGFloat = 0.35
    var didStop: (() -> Void)?

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    func start() {
        guard displayLink == nil, scrollView != nil else { return }
        DispatchQueue.main.async {
            self.displayLink = CADisplayLink(target: self, selector: #selector(self.handleTick(_:)))
            self.lastTimestamp = nil
            self.displayLink?.preferredFramesPerSecond = 60
            self.displayLink?.add(to: .main, forMode: .common)
            print("[AutoScroll] start() called. scrollView: \(String(describing: self.scrollView)), speed: \(self.speed)")
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        if let didStop = didStop {
            DispatchQueue.main.async { didStop() }
        }
        print("[AutoScroll] stop() called")
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

        let elapsed = link.timestamp - (lastTimestamp ?? link.timestamp)
        lastTimestamp = link.timestamp
        let distance = CGFloat(elapsed) * speed * 220

        let maxYOffset = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        if maxYOffset <= 0 {
            print("[AutoScroll] nothing to scroll: contentSize.height=\(scrollView.contentSize.height), bounds.height=\(scrollView.bounds.height)")
            return
        }
        if maxYOffset <= 0 {
            // Nothing to scroll
            return
        }

        let nextOffset = min(scrollView.contentOffset.y + distance, maxYOffset)

        // Debug occasional tick info
        // (kept light to avoid console spam)
        if distance > 0 {
            print("[AutoScroll] tick: offset=\(scrollView.contentOffset.y) distance=\(distance) next=\(nextOffset) max=\(maxYOffset)")
        }

        if scrollView.contentOffset.y >= maxYOffset {
            print("[AutoScroll] reached bottom")
            stop()
            return
        }

        let target = CGPoint(x: scrollView.contentOffset.x, y: nextOffset)
        UIView.performWithoutAnimation {
            scrollView.setContentOffset(target, animated: false)
        }
    }
}
